import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wildbit/data/osm/waymarked_trails_client.dart';
import 'package:wildbit/data/repositories/osm_trail_repository.dart';

void main() {
  // Runs first, deliberately: OverpassEndpoints.instance is a process-wide
  // singleton, and the other two tests below push every public endpoint
  // into cooldown. This test needs a real (non-cooling-down) endpoint to
  // exercise the "Overpass succeeds" path, so it must run before that
  // shared state is poisoned.
  test(
    'still returns way segments when Waymarked Trails is unreachable',
    () async {
      final overpass = _FakeOverpassClient();
      final repository = OsmTrailRepository(
        httpClient: overpass,
        waymarkedClient: WaymarkedTrailsClient(
          httpClient: _FakeFailingClient(),
        ),
      );

      final trails = await repository.findNearby(
        position: const LatLng(46.07, 11.12),
      );

      expect(trails, hasLength(1));
      expect(trails.single.isCuratedRoute, isFalse);
      expect(trails.single.name, 'Sentiero cached');
    },
  );

  test(
    'reuses a nearby search and serves it when Overpass goes offline',
    () async {
      final client = _FakeOverpassClient();
      // A separate fake client for Waymarked Trails, so its own HTTP calls
      // (an independent, always-empty source in this test) don't inflate
      // the Overpass-specific call count this test actually asserts on.
      final repository = OsmTrailRepository(
        httpClient: client,
        waymarkedClient: WaymarkedTrailsClient(httpClient: _FakeEmptyClient()),
      );
      const position = LatLng(46.07, 11.12);

      final first = await repository.findNearby(position: position);
      final cached = await repository.findNearby(position: position);

      expect(first, hasLength(1));
      expect(cached.single.name, 'Sentiero cached');
      expect(first.single.lengthKm, 1.2);
      expect(client.calls, 1);

      client.fail = true;
      final stale = await repository.findNearby(
        position: position,
        forceRefresh: true,
      );
      expect(stale.single.name, 'Sentiero cached');
      expect(client.calls, greaterThan(1));
    },
  );

  test(
    'still returns curated routes when every Overpass endpoint fails',
    () async {
      final overpass = _FakeOverpassClient()..fail = true;
      final repository = OsmTrailRepository(
        httpClient: overpass,
        waymarkedClient: WaymarkedTrailsClient(
          httpClient: _FakeWaymarkedClient(),
        ),
      );

      final trails = await repository.findNearby(
        position: const LatLng(44.43, 12.21),
      );

      expect(trails, hasLength(1));
      expect(trails.single.isCuratedRoute, isTrue);
      expect(trails.single.name, 'Via del Bosco');
    },
  );
}

class _FakeOverpassClient extends http.BaseClient {
  int calls = 0;
  bool fail = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (fail) throw StateError('offline');
    final body = jsonEncode({
      'elements': [
        {
          'type': 'way',
          'id': 42,
          'center': {'lat': 46.071, 'lon': 11.121},
          'tags': {
            'highway': 'path',
            'name': 'Sentiero cached',
            'distance': '1200 m',
          },
        },
      ],
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

class _FakeEmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({'results': <dynamic>[]});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

/// Answers both Waymarked Trails calls a search makes: the area listing,
/// then the per-route details lookup for the one match it reports.
class _FakeWaymarkedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Map<String, dynamic> body;
    if (request.url.path.contains('/list/by_area')) {
      body = {
        'results': [
          {'id': 555, 'group': 'REG'},
        ],
      };
    } else {
      body = {
        'id': 555,
        'name': 'Via del Bosco',
        'group': 'REG',
        'bbox': [1359000.0, 5544000.0, 1359200.0, 5544200.0],
        'official_length': 8000.0,
        'tags': <String, dynamic>{},
      };
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
    );
  }
}

class _FakeFailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('Waymarked Trails unreachable');
  }
}
