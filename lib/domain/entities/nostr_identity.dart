/// The user's Nostr identity, known only by its public key — WildBit never
/// sees or stores the private key (nsec); all signing/decryption happens
/// inside the external Amber app.
class NostrIdentity {
  const NostrIdentity({required this.pubkeyHex, required this.npub});

  final String pubkeyHex;
  final String npub;
}
