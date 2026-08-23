import 'package:amberflutter/amberflutter.dart';
import 'package:nostr_tools/nostr_tools.dart';

import '../../domain/entities/nostr_identity.dart';

final _hexPubkey = RegExp(r'^[0-9a-fA-F]{64}$');

/// Thin wrapper around the Amber (NIP-55) external signer: WildBit only ever
/// asks Amber for a public key or to encrypt/decrypt on its behalf — the
/// private key (nsec) never enters this app's process.
class AmberSignerService {
  final _amber = Amberflutter();

  Future<bool> isInstalled() => _amber.isAppInstalled();

  /// Requests the user's public key from Amber. Returns null if the user
  /// declines, Amber isn't installed, or the response is malformed.
  Future<NostrIdentity?> login() async {
    try {
      final result = await _amber.getPublicKey(
        permissions: const [
          Permission(type: 'sign_event'),
          Permission(type: 'nip44_encrypt'),
          Permission(type: 'nip44_decrypt'),
        ],
      );
      final raw = result['signature'] as String? ?? '';
      if (raw.isEmpty) return null;

      final hex = raw.startsWith('npub')
          ? Nip19().decode(raw)['data'] as String
          : raw;
      if (!_hexPubkey.hasMatch(hex)) return null;

      return NostrIdentity(pubkeyHex: hex, npub: Nip19().npubEncode(hex));
    } catch (_) {
      return null;
    }
  }

  Future<Map<dynamic, dynamic>> signEvent({
    required String currentUser,
    required String eventJson,
  }) => _amber.signEvent(currentUser: currentUser, eventJson: eventJson);

  /// Encrypts [plaintext] to the identity's own public key (NIP-44
  /// "encrypt to self"): only the matching nsec, via Amber, can decrypt it
  /// again. Used to make the local database encryption key recoverable from
  /// the user's Nostr identity instead of only living on this device.
  Future<String?> encryptToSelf(String plaintext, String pubkeyHex) async {
    try {
      final result = await _amber.nip44Encrypt(
        plaintext: plaintext,
        currentUser: pubkeyHex,
        pubKey: pubkeyHex,
      );
      final out = result['signature'] as String?;
      return (out != null && out.isNotEmpty) ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> decryptToSelf(String ciphertext, String pubkeyHex) async {
    try {
      final result = await _amber.nip44Decrypt(
        ciphertext: ciphertext,
        currentUser: pubkeyHex,
        pubKey: pubkeyHex,
      );
      final out = result['signature'] as String?;
      return (out != null && out.isNotEmpty) ? out : null;
    } catch (_) {
      return null;
    }
  }
}
