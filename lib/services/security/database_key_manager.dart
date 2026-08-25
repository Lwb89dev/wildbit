import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/nostr_identity.dart';
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
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _cachedKeyStorageKey = 'wildbit.db_key_v1';
  static const _wrappedKeyPrefsKey = 'wildbit.db_key_wrapped_v1';
  static const _linkedPubkeyPrefsKey = 'wildbit.nostr_pubkey_v1';
  static const _linkedNpubPrefsKey = 'wildbit.nostr_npub_v1';
  static const nsecStorageKey = 'wildbit.nostr_nsec_v1';

  final FlutterSecureStorage _secureStorage;

  /// Returns the raw hex-encoded database key, generating and caching one
  /// on first run. Safe to call before any Nostr identity is linked.
  Future<String> resolveKey() async {
    final cached = await _secureStorage.read(key: _cachedKeyStorageKey);
    if (cached != null) return cached;

    final generated = _generateHexKey();
    await _secureStorage.write(key: _cachedKeyStorageKey, value: generated);
    return generated;
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
    final key = await resolveKey();
    final wrapped = await signer.encryptToSelf(key, identity.pubkeyHex);
    if (wrapped == null) return false;

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
    if (recovered == null) return null;
    await _secureStorage.write(key: _cachedKeyStorageKey, value: recovered);
    return recovered;
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
