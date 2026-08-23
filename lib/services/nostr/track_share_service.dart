import 'dart:async';
import 'dart:convert';

import 'package:nostr_tools/nostr_tools.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/saved_track.dart';
import '../security/database_key_manager.dart';
import 'amber_signer_service.dart';

/// Publishes a completed hike as a signed Nostr note. Exact GPS points are
/// public once shared, so callers must always obtain explicit user consent.
class TrackShareService {
  TrackShareService({
    required DatabaseKeyManager keyManager,
    required AmberSignerService amber,
  }) : _keyManager = keyManager,
       _amber = amber;

  static const _relays = ['wss://nos.lol', 'wss://relay.primal.net'];
  final DatabaseKeyManager _keyManager;
  final AmberSignerService _amber;

  Future<void> publish(SavedTrack track) async {
    final identity = await _keyManager.linkedIdentity;
    if (identity == null) throw StateError('Collega prima un’identità Nostr.');
    final content = jsonEncode({
      'type': 'wildbit_hike',
      'name': track.name,
      'distance_m': track.distanceMeters.round(),
      'duration_s': track.durationSeconds,
      'average_pace_s_per_km': track.distanceMeters <= 0
          ? null
          : (track.durationSeconds * 1000 / track.distanceMeters).round(),
      'track': [
        for (final point in track.points)
          [
            point.position.latitude,
            point.position.longitude,
            point.timestamp.millisecondsSinceEpoch,
          ],
      ],
    });
    final unsigned = Event(
      pubkey: identity.pubkeyHex,
      created_at: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 1,
      tags: const [
        ['t', 'wildbit'],
        ['t', 'hiking'],
      ],
      content: content,
    );
    final nsec = await _keyManager.storedNsec;
    final Map<String, dynamic> event;
    if (nsec != null) {
      final privateKey = Nip19().decode(nsec)['data'] as String;
      event = EventApi().finishEvent(unsigned, privateKey).toJson();
    } else {
      final result = await _amber.signEvent(
        currentUser: identity.pubkeyHex,
        eventJson: jsonEncode(unsigned.toJson()),
      );
      final raw = result['signature'] as String?;
      if (raw == null || raw.isEmpty)
        throw StateError('Firma Amber annullata.');
      event = jsonDecode(raw) as Map<String, dynamic>;
    }
    final accepted = await Future.wait(
      _relays.map((relay) => _publish(relay, event)),
    );
    if (!accepted.any((ok) => ok))
      throw StateError('I relay non hanno accettato il percorso.');
  }

  Future<bool> _publish(String relay, Map<String, dynamic> event) async {
    WebSocketChannel? socket;
    StreamSubscription? sub;
    try {
      socket = WebSocketChannel.connect(Uri.parse(relay));
      final response = Completer<bool>();
      sub = socket.stream.listen(
        (raw) {
          if (response.isCompleted || raw is! String) return;
          try {
            final message = jsonDecode(raw) as List;
            if (message.length >= 3 &&
                message[0] == 'OK' &&
                message[1] == event['id']) {
              response.complete(message[2] == true);
            }
          } catch (_) {}
        },
        onError: (_) => response.complete(false),
        onDone: () => response.complete(false),
      );
      await socket.ready.timeout(const Duration(seconds: 5));
      socket.sink.add(jsonEncode(['EVENT', event]));
      return await response.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      await sub?.cancel();
      await socket?.sink.close();
    }
  }
}
