import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:nostr_tools/nostr_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildbit/data/osm/waymarked_trails_client.dart';
import 'package:wildbit/data/repositories/drift_track_repository.dart';
import 'package:wildbit/data/repositories/osm_trail_repository.dart';
import 'package:wildbit/data/weather/weather_client.dart';
import 'package:wildbit/domain/entities/geo_fix.dart';
import 'package:wildbit/domain/entities/saved_track.dart';
import 'package:wildbit/domain/enums/track_source.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';
import 'package:wildbit/services/nostr/track_share_payload.dart';
import 'package:wildbit/services/nostr/track_share_service.dart';
import 'package:wildbit/storage/database.dart';

SavedTrack _straightTrack({required int points, double stepDegrees = .0005}) =>
    SavedTrack(
      name: 'Dalla porta di casa',
      createdAt: DateTime.utc(2026, 5, 1),
      distanceMeters: 2000,
      durationSeconds: 1800,
      elevationGainMeters: 120,
      source: TrackSource.recorded,
      points: [
        for (var index = 0; index < points; index++)
          GeoFix(
            position: LatLng(46, 11 + index * stepDegrees),
            timestamp: DateTime.utc(2026, 5, 1, 8, index),
          ),
      ],
    );

void main() {
  group('track deletion', () {
    test('removes every GPS point of the deleted track', () async {
      final database = WildBitDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftTrackRepository(database);
      final kept = await repository.saveTrack(_straightTrack(points: 4));
      final deleted = await repository.saveTrack(_straightTrack(points: 6));

      await repository.deleteTrack(deleted);

      final remaining = await database.select(database.trackPoints).get();
      expect(remaining, hasLength(4));
      expect(remaining.every((point) => point.trackId == kept), isTrue);
    });

    test('cascades point deletion through enforced foreign keys', () async {
      final database = WildBitDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final id = await DriftTrackRepository(
        database,
      ).saveTrack(_straightTrack(points: 3));

      await (database.delete(
        database.tracks,
      )..where((track) => track.id.equals(id))).go();

      expect(await database.select(database.trackPoints).get(), isEmpty);
    });
  });

  test('accepts only database keys in the generated hex format', () {
    expect(WildBitDatabase.isValidKey('ab' * 32), isTrue);
    expect(WildBitDatabase.isValidKey('AB' * 32), isFalse);
    expect(WildBitDatabase.isValidKey('ab' * 31), isFalse);
    expect(WildBitDatabase.isValidKey("${'a' * 62}'\""), isFalse);
  });

  group('Nostr privacy zone', () {
    test('publishes the whole track unless asked to hide endpoints', () {
      final track = _straightTrack(points: 20);
      final payload = TrackSharePayload.fromTrack(track);
      expect(payload['track'] as List, hasLength(20));
    });

    test('drops points near start and finish, bounds included', () {
      // 20 points about 39 m apart: 200 m covers six points at each end.
      final track = _straightTrack(points: 20);
      final payload = TrackSharePayload.fromTrack(track, hideEndpoints: true);
      final published = payload['track'] as List;
      expect(published, hasLength(8));
      final firstLongitude = (published.first as List)[1] as double;
      final lastLongitude = (published.last as List)[1] as double;
      expect(firstLongitude, closeTo(11 + 6 * .0005, 1e-9));
      expect(lastLongitude, closeTo(11 + 13 * .0005, 1e-9));
      final bbox = payload['bbox'] as Map<String, num>;
      expect(bbox['west'], closeTo(firstLongitude, 1e-9));
      expect(bbox['east'], closeTo(lastLongitude, 1e-9));
      // Statistics still describe the complete hike.
      expect(payload['distance_m'], 2000);
      expect(payload['duration_s'], 1800);
    });

    test('refuses a track that would publish fewer than two points', () {
      final track = _straightTrack(points: 5);
      expect(
        () => TrackSharePayload.fromTrack(track, hideEndpoints: true),
        throwsStateError,
      );
    });
  });

  group('external signer results', () {
    final keys = KeyApi();
    final privateKey = keys.generatePrivateKey();
    final pubkey = keys.getPublicKey(privateKey);
    Event unsignedEvent() => Event(
      pubkey: pubkey,
      created_at: 1777000000,
      kind: 1301,
      tags: [
        ['t', 'wildbit'],
        ['title', 'Anello'],
      ],
      content: '{"type":"wildbit_hike"}',
      verify: false,
    );
    final signed = EventApi().finishEvent(unsignedEvent(), privateKey);

    test('accepts the approved event returned as JSON', () {
      final event = TrackShareService.signedEventFromSigner(
        {'event': jsonEncode(signed.toJson())},
        unsignedEvent(),
        pubkey,
      );
      expect(event['id'], signed.id);
      expect(event['sig'], signed.sig);
    });

    test('attaches a bare NIP-55 signature to the approved event', () {
      final event = TrackShareService.signedEventFromSigner(
        {'signature': signed.sig},
        unsignedEvent(),
        pubkey,
      );
      expect(event['id'], signed.id);
      expect(event['content'], signed.content);
    });

    test('rejects an event whose content differs from the approved one', () {
      final tampered = {...signed.toJson(), 'content': '{"track":[]}'};
      expect(
        () => TrackShareService.signedEventFromSigner(
          {'event': jsonEncode(tampered)},
          unsignedEvent(),
          pubkey,
        ),
        throwsA(
          isA<TrackShareException>().having(
            (error) => error.messageKey,
            'messageKey',
            'share.signRejected',
          ),
        ),
      );
    });

    test('rejects a forged signature and reports a cancelled request', () {
      expect(
        () => TrackShareService.signedEventFromSigner(
          {'signature': 'ab' * 64},
          unsignedEvent(),
          pubkey,
        ),
        throwsA(isA<TrackShareException>()),
      );
      expect(
        () => TrackShareService.signedEventFromSigner(
          const {},
          unsignedEvent(),
          pubkey,
        ),
        throwsA(
          isA<TrackShareException>().having(
            (error) => error.messageKey,
            'messageKey',
            'share.signCancelled',
          ),
        ),
      );
    });
  });

  test(
    'keeps Explore results in the encrypted database, not preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'wildbit.explore.cache.v1': '{"version":1,"entries":{}}',
      });
      final database = WildBitDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const position = LatLng(46.07, 11.12);
      final online = OsmTrailRepository(
        httpClient: _TrailClient(),
        waymarkedClient: WaymarkedTrailsClient(
          httpClient: _EmptyRoutesClient(),
        ),
        database: database,
      );
      expect((await online.findNearby(position: position)).single.name, 'Rio');

      var rows = await database.select(database.cachedMapCells).get();
      for (var attempt = 0; attempt < 100 && rows.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        rows = await database.select(database.cachedMapCells).get();
      }
      expect(rows.single.cellKey, startsWith('explore.v1:'));
      expect(rows.single.cellKey, isNot(contains('46.07')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('wildbit.explore.cache.v1'), isFalse);

      // A later session without network serves the stored results.
      final offline = OsmTrailRepository(
        httpClient: _OfflineClient(),
        waymarkedClient: WaymarkedTrailsClient(httpClient: _OfflineClient()),
        database: database,
      );
      expect((await offline.findNearby(position: position)).single.name, 'Rio');
    },
  );

  test('sends the weather service a position rounded to about 1 km', () async {
    final client = _RecordingClient();
    await OpenMeteoClient(
      httpClient: client,
    ).fetchCurrent(const LatLng(46.123456, 11.987654));
    final query = client.requests.single.url.queryParameters;
    expect(query['latitude'], '46.12');
    expect(query['longitude'], '11.99');
  });

  test('longitude overlap fast path agrees with the range computation', () {
    const intervals = [
      (-10.0, 5.0),
      (4.0, 20.0),
      (20.5, 21.0),
      (-180.0, -179.0),
      (179.0, 180.0),
      (170.0, -170.0),
    ];
    for (final first in intervals) {
      for (final second in intervals) {
        for (final margin in const [0.0, .002, 1.0]) {
          expect(
            MapRenderingBudget.longitudeIntervalsOverlap(
              first.$1,
              first.$2,
              second.$1,
              second.$2,
              margin: margin,
            ),
            _referenceOverlap(first, second, margin),
            reason: '$first vs $second margin $margin',
          );
        }
      }
    }
  });
}

/// The range-list algorithm the culling used before its fast path.
bool _referenceOverlap(
  (double, double) first,
  (double, double) second,
  double margin,
) {
  double normalize(double value) {
    var normalized = value;
    while (normalized < -180) {
      normalized += 360;
    }
    while (normalized > 180) {
      normalized -= 360;
    }
    return normalized;
  }

  List<(double, double)> ranges(double west, double east) {
    final span = east - west < 0 ? east - west + 360 : east - west;
    if (span >= 360 - 1e-9) return const [(-180, 180)];
    final wraps = west > east;
    final start = normalize(west - margin);
    final end = normalize(east + margin);
    if (!wraps && start <= end) return [(start, end)];
    if (wraps && start > end) return [(start, 180), (-180, end)];
    return [(start < end ? start : end, start > end ? start : end)];
  }

  for (final a in ranges(first.$1, first.$2)) {
    for (final b in ranges(second.$1, second.$2)) {
      if (a.$1 <= b.$2 && b.$1 <= a.$2) return true;
    }
  }
  return false;
}

class _TrailClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'elements': [
        {
          'type': 'way',
          'id': 7,
          'center': {'lat': 46.071, 'lon': 11.121},
          'tags': {'highway': 'path', 'name': 'Rio'},
        },
      ],
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

class _EmptyRoutesClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'results': <dynamic>[]}))),
        200,
      );
}

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw StateError('offline');
}

class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = utf8.encode(
      jsonEncode({
        'current': {'temperature_2m': 12.0, 'weather_code': 0, 'is_day': 1},
      }),
    );
    return http.StreamedResponse(Stream.value(body), 200);
  }
}
