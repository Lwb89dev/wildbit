import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/services/nostr/nostr_profile_service.dart';

void main() {
  test('parses Nostr display name, fallback name and picture', () {
    final profile = NostrProfile.fromContent(
      '{"name":"bitwalker","display_name":"Bit Walker",'
      '"picture":"https://example.com/avatar.png"}',
    );

    expect(profile.preferredName, 'Bit Walker');
    expect(profile.pictureUri?.host, 'example.com');
  });

  test('rejects unsafe profile image schemes', () {
    final profile = NostrProfile.fromContent(
      '{"display_name":"Bit","picture":"javascript:alert(1)"}',
    );

    expect(profile.preferredName, 'Bit');
    expect(profile.pictureUri, isNull);
  });
}
