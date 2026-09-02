import 'dart:async';
import 'dart:convert';

import 'package:nostr_tools/nostr_tools.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:drift/drift.dart';

import '../../domain/entities/saved_track.dart';
import '../../domain/entities/track_summary.dart';
import '../security/database_key_manager.dart';
import '../../storage/database.dart';
import 'amber_signer_service.dart';
import 'track_share_payload.dart';

/// Publishes a completed hike as a signed Nostr note. Exact GPS points are
/// public once shared, so callers must always obtain explicit user consent.
class TrackShareService {
  factory TrackShareService({
    required WildBitDatabase database,
    required DatabaseKeyManager keyManager,
    required AmberSignerService amber,
  }) => TrackShareService._(database, keyManager, amber);

  TrackShareService._(this._database, this._keyManager, this._amber);

  static const _relays = ['wss://nos.lol', 'wss://relay.primal.net'];
  final WildBitDatabase _database;
  final DatabaseKeyManager _keyManager;
  final AmberSignerService _amber;

  /// Kind 1301 ("Workout Record") is the closest thing to a de-facto standard
  /// for GPS activity events on Nostr today — established by RUNSTR/
  /// HealthNoteLabs, not (yet) a ratified NIP in the core nostr-protocol/nips
  /// repo. There's also a competing draft, NIP-113 "Activity Events"
  /// (kind 30100), still under review as of this writing. 1301 is what this
  /// picks: it already has a real, working client reading it, which matters
  /// more for "will anything ever render this" than a spec with no adopters
  /// yet. Because it isn't kind 1, generic social clients (Damus, Primal...)
  /// will not show it in a normal feed — that's the tradeoff for structured,
  /// stat-bearing data over generic visibility.
  Future<TrackPublishResult> publish(SavedTrack track) async {
    final identity = await _keyManager.linkedIdentity;
    if (identity == null) throw StateError('Collega prima un’identità Nostr.');
    final summary = TrackSummary.fromTrack(track);
    final content = jsonEncode(TrackSharePayload.fromTrack(track));
    final unsigned = Event(
      pubkey: identity.pubkeyHex,
      created_at: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 1301,
      tags: [
        ['d', 'wildbit-${track.id ?? DateTime.now().millisecondsSinceEpoch}'],
        ['title', track.name],
        ['activity_type', 'hiking'],
        ['distance', (summary.distanceMeters / 1000).toStringAsFixed(2), 'km'],
        ['duration', summary.durationSeconds.toString()],
        ['elevation_gain', summary.elevationGainMeters.round().toString(), 'm'],
        const ['t', 'wildbit'],
        const ['t', 'hiking'],
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
      if (raw == null || raw.isEmpty) {
        throw StateError('Firma Amber annullata.');
      }
      event = jsonDecode(raw) as Map<String, dynamic>;
    }
    if (await _publishToAnyRelay(event)) {
      return const TrackPublishResult.published();
    }
    await _queue(event, reason: 'Nessun relay ha accettato l’evento.');
    return const TrackPublishResult.queued();
  }

  /// Retries at most a few explicitly consented, already-signed events. This
  /// is deliberately called when the user re-enters Traccia, not via a timer
  /// or a background worker that could waste battery while hiking offline.
  Future<int> retryQueued({int maxEvents = 1}) async {
    final pending =
        await (_database.select(_database.pendingNostrPublications)
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..limit(maxEvents.clamp(1, 3)))
            .get();
    var delivered = 0;
    for (final publication in pending) {
      try {
        final event = jsonDecode(publication.eventJson) as Map<String, dynamic>;
        if (await _publishToAnyRelay(event)) {
          await (_database.delete(
            _database.pendingNostrPublications,
          )..where((row) => row.id.equals(publication.id))).go();
          delivered++;
        } else {
          await _markFailed(publication.id, publication.retryCount);
        }
      } catch (_) {
        await _markFailed(publication.id, publication.retryCount);
      }
    }
    return delivered;
  }

  Future<bool> _publishToAnyRelay(Map<String, dynamic> event) async {
    final accepted = await Future.wait(
      _relays.map((relay) => _publish(relay, event)),
    );
    return accepted.any((ok) => ok);
  }

  Future<void> _queue(Map<String, dynamic> event, {required String reason}) =>
      _database
          .into(_database.pendingNostrPublications)
          .insert(
            PendingNostrPublicationsCompanion.insert(
              eventJson: jsonEncode(event),
              createdAt: DateTime.now(),
              lastError: Value(reason),
            ),
          );

  Future<void> _markFailed(int id, int retryCount) =>
      (_database.update(
        _database.pendingNostrPublications,
      )..where((row) => row.id.equals(id))).write(
        PendingNostrPublicationsCompanion(
          retryCount: Value(retryCount + 1),
          lastAttemptAt: Value(DateTime.now()),
          lastError: const Value('Relay non raggiungibile.'),
        ),
      );

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

/// Outcome shown by the UI after an explicitly confirmed Nostr publication.
/// A queued event is already signed and preserved in the encrypted database;
/// it is never silently discarded when the user is hiking without coverage.
class TrackPublishResult {
  const TrackPublishResult._(this.queued);

  const TrackPublishResult.published() : this._(false);
  const TrackPublishResult.queued() : this._(true);

  final bool queued;
}
