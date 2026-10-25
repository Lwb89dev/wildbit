import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/nostr_identity.dart';
import '../../storage/database.dart';
import '../nostr/amber_signer_service.dart';

/// Owns the local database's encryption key.
///
/// The database is always encrypted, with or without a Nostr identity:
/// on first run a random key is generated and cached (Android Keystore
/// backed, via [FlutterSecureStorage]) so the app works with no account at
/// all. Linking a Nostr identity via Amber does not replace that key — it
/// wraps it (NIP-44 "encrypt to self") and stores the wrapped copy, so the
/// *same* key can later be recovered from the user's nsec (via Amber) rather
/// than only ever living on this one device. That recovery path is what
/// makes exporting the encrypted database file a meaningful backup.
class DatabaseKeyManager {
  DatabaseKeyManager({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          // The plugin default wipes *all* entries on any decryption error.
          // A transient Keystore failure would then destroy the only copy of
          // the database key and, on the next launch, a new key would make
          // every recorded hike unreadable. Errors must surface instead.
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  static const _cachedKeyStorageKey = 'wildbit.db_key_v1';
  static const _wrappedKeyPrefsKey = 'wildbit.db_key_wrapped_v1';
  static const _linkedPubkeyPrefsKey = 'wildbit.nostr_pubkey_v1';
  static const _linkedNpubPrefsKey = 'wildbit.nostr_npub_v1';
  static const nsecStorageKey = 'wildbit.nostr_nsec_v1';

  final FlutterSecureStorage _secureStorage;

  /// Returns the raw hex-encoded database key, generating and caching one
  /// on first run. Safe to call before any Nostr identity is linked.
  ///
  /// Only for startup, before the database is opened: when a new key has to
  /// be generated, a database file left without its key is moved aside.
  Future<String> resolveKey() async {
    final cached = await currentKey;
    if (cached != null) return cached;

    await WildBitDatabaseFile.archiveUnreadable();
    final generated = _generateHexKey();
    await _secureStorage.write(key: _cachedKeyStorageKey, value: generated);
    return generated;
  }

  /// The key of the database in use, or null if secure storage has none.
  /// Never generates a key: wrapping a fresh one for recovery would not
  /// match the database that is already open.
  Future<String?> get currentKey async {
    final key = await _secureStorage.read(key: _cachedKeyStorageKey);
    return key != null && WildBitDatabase.isValidKey(key) ? key : null;
  }

  Future<NostrIdentity?> get linkedIdentity async {
    final prefs = await SharedPreferences.getInstance();
    final pubkey = prefs.getString(_linkedPubkeyPrefsKey);
    final npub = prefs.getString(_linkedNpubPrefsKey);
    if (pubkey == null || npub == null) return null;
    return NostrIdentity(pubkeyHex: pubkey, npub: npub);
  }

  /// Wraps the current database key to [identity]'s own public key and
  /// stores the ciphertext, so it can be recovered later via Amber given
  /// only the matching nsec. Returns false if Amber failed to encrypt.
  Future<bool> linkNostrIdentity(
    NostrIdentity identity,
    AmberSignerService signer,
  ) async {
    final key = await currentKey;
    if (key == null) return false;
    final wrapped = await signer.encryptToSelf(key, identity.pubkeyHex);
    if (wrapped == null) return false;

    // The two signing modes are mutually exclusive. Keeping an older nsec
    // after switching to Amber could sign an event for the newly linked
    // pubkey with the previous account's private key.
    await _secureStorage.delete(key: nsecStorageKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wrappedKeyPrefsKey, wrapped);
    await prefs.setString(_linkedPubkeyPrefsKey, identity.pubkeyHex);
    await prefs.setString(_linkedNpubPrefsKey, identity.npub);
    return true;
  }

  /// True when this looks like a fresh install (or a restore onto a new
  /// device) that inherited Nostr-link metadata — via Android's default
  /// Auto Backup of SharedPreferences — but not the actual database key,
  /// which lives only in this device's Keystore and does not survive an
  /// uninstall. The caller should offer Amber recovery via
  /// [recoverKeyFromAmber] before ever calling [resolveKey], which would
  /// otherwise silently generate a new key that can't open a restored
  /// backup encrypted with the original one.
  Future<bool> hasRecoverableIdentity() async {
    if (await _secureStorage.read(key: _cachedKeyStorageKey) != null) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_wrappedKeyPrefsKey) != null &&
        prefs.getString(_linkedPubkeyPrefsKey) != null;
  }

  /// Recovers the original database key from its NIP-44-wrapped copy via
  /// Amber, caching it locally on success so later launches use
  /// [resolveKey]'s normal fast path again. Returns null if there is
  /// nothing to recover or Amber declines/fails to decrypt.
  Future<String?> recoverKeyFromAmber(AmberSignerService signer) async {
    final prefs = await SharedPreferences.getInstance();
    final wrapped = prefs.getString(_wrappedKeyPrefsKey);
    final pubkey = prefs.getString(_linkedPubkeyPrefsKey);
    if (wrapped == null || pubkey == null) return null;
    final recovered = await signer.decryptToSelf(wrapped, pubkey);
    // The plaintext comes from another app and ends up in a PRAGMA: accept
    // only a key in the exact format this class generates.
    if (recovered == null || !WildBitDatabase.isValidKey(recovered)) {
      return null;
    }
    await _secureStorage.write(key: _cachedKeyStorageKey, value: recovered);
    return recovered;
  }

  /// Drops a wrapped key that no longer matches the database, after the user
  /// chose to start over instead of recovering it.
  Future<void> discardRecoveryData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wrappedKeyPrefsKey);
  }

  Future<void> unlinkNostrIdentity() async {
    await _secureStorage.delete(key: nsecStorageKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wrappedKeyPrefsKey);
    await prefs.remove(_linkedPubkeyPrefsKey);
    await prefs.remove(_linkedNpubPrefsKey);
  }

  /// Stores an explicitly entered nsec only in platform secure storage.
  /// It is never written to SharedPreferences or included in backups.
  Future<void> linkNsecIdentity(NostrIdentity identity, String nsec) async {
    await _secureStorage.write(key: nsecStorageKey, value: nsec);
    final prefs = await SharedPreferences.getInstance();
    // A wrapped key created for a previous Amber identity cannot be recovered
    // by this nsec. Do not leave mismatched recovery metadata in Auto Backup.
    await prefs.remove(_wrappedKeyPrefsKey);
    await prefs.setString(_linkedPubkeyPrefsKey, identity.pubkeyHex);
    await prefs.setString(_linkedNpubPrefsKey, identity.npub);
  }

  Future<String?> get storedNsec => _secureStorage.read(key: nsecStorageKey);

  static String _generateHexKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
