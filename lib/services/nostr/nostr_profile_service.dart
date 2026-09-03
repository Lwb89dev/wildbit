import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Public profile fields advertised by a Nostr kind-0 metadata event.
///
/// Profile metadata is optional and untrusted: it is only presentation data,
/// never used for identity, signing, or database encryption.
class NostrProfile {
  const NostrProfile({this.name, this.displayName, this.picture});

  final String? name;
  final String? displayName;
  final String? picture;

  String? get preferredName {
    for (final value in [displayName, name]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Uri? get pictureUri {
    final raw = picture?.trim();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri;
  }

  factory NostrProfile.fromContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map) return const NostrProfile();
    String? stringValue(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return NostrProfile(
      name: stringValue(decoded['name']),
      displayName:
          stringValue(decoded['display_name']) ??
          stringValue(decoded['displayName']),
      picture: stringValue(decoded['picture']),
    );
  }
}

/// Reads the latest public kind-0 profile from a small set of relays.
///
/// This is deliberately best-effort: settings render immediately and a
/// relay outage simply leaves the stable npub fallback in place.
class NostrProfileService {
  NostrProfileService._();

  static final instance = NostrProfileService._();

  static const _relays = <String>[
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://relay.damus.io',
  ];

  final Map<String, ({NostrProfile? profile, DateTime fetchedAt})> _cache = {};

  Future<NostrProfile?> fetch(String pubkeyHex) async {
    final cached = _cache[pubkeyHex];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 15)) {
      return cached.profile;
    }

    final results = await Future.wait(
      _relays.map((relay) => _fetchFromRelay(relay, pubkeyHex)),
    );
    NostrProfile? profile;
    for (final candidate in results) {
      if (candidate != null && candidate.preferredName != null) {
        profile = candidate;
        break;
      }
      profile ??= candidate;
    }
    _cache[pubkeyHex] = (profile: profile, fetchedAt: DateTime.now());
    return profile;
  }

  Future<NostrProfile?> _fetchFromRelay(String relay, String pubkeyHex) async {
    WebSocketChannel? socket;
    StreamSubscription? subscription;
    try {
      socket = WebSocketChannel.connect(Uri.parse(relay));
      final result = Completer<NostrProfile?>();
      subscription = socket.stream.listen(
        (raw) {
          if (result.isCompleted || raw is! String) return;
          try {
            final message = jsonDecode(raw);
            if (message is! List ||
                message.length < 3 ||
                message[0] != 'EVENT') {
              return;
            }
            final event = message[2];
            if (event is! Map ||
                event['kind'] != 0 ||
                event['pubkey']?.toString().toLowerCase() !=
                    pubkeyHex.toLowerCase()) {
              return;
            }
            final content = event['content'];
            if (content is! String) return;
            result.complete(NostrProfile.fromContent(content));
          } catch (_) {
            // Ignore malformed relay frames; another relay can still answer.
          }
        },
        onError: (_) {
          if (!result.isCompleted) result.complete(null);
        },
        onDone: () {
          if (!result.isCompleted) result.complete(null);
        },
      );
      await socket.ready.timeout(const Duration(seconds: 3));
      socket.sink.add(
        jsonEncode([
          'REQ',
          'wildbit-profile-$pubkeyHex',
          {
            'kinds': [0],
            'authors': [pubkeyHex],
            'limit': 1,
          },
        ]),
      );
      return await result.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      await socket?.sink.close();
    }
  }
}
