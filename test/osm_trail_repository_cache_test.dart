import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wildbit/data/repositories/osm_trail_repository.dart';

void main() {
  test('reuses a nearby search and serves it when Overpass goes offline', () async {
    final client = _FakeOverpassClient();
    final repository = OsmTrailRepository(httpClient: client);
    const position = LatLng(46.07, 11.12);

    final first = await repository.findNearby(position: position);
    final cached = await repository.findNearby(position: position);

    expect(first, hasLength(1));
    expect(cached.single.name, 'Sentiero cached');
    expect(client.calls, 1);

    client.fail = true;
    final stale = await repository.findNearby(
      position: position,
      forceRefresh: true,
    );
    expect(stale.single.name, 'Sentiero cached');
    expect(client.calls, greaterThan(1));
  });
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
          'tags': {'highway': 'path', 'name': 'Sentiero cached'},
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
