import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wildbit/data/osm/waymarked_trails_client.dart';

void main() {
  test('routeGeometry flattens ordered way geometry, skipping shared joints', () async {
    // Mirrors a real `details/relation/{id}` response's shape (two ways
    // sharing an endpoint, as verified against Waymarked Trails' own PC2
    // example): the shared node must appear only once in the flattened path.
    final body = jsonEncode({
      'route': {
        'main': [
          {
            'ways': [
              {
                'geometry': {
                  'coordinates': [
                    [1224514.0, 5771469.0],
                    [1224600.0, 5771500.0],
                  ],
                },
              },
              {
                'geometry': {
                  'coordinates': [
                    [1224600.0, 5771500.0],
                    [1224700.0, 5771600.0],
                  ],
                },
              },
            ],
          },
        ],
        'appendices': [],
      },
    });
    final client = WaymarkedTrailsClient(
      httpClient: _FakeClient((_) => body),
    );

    final geometry = await client.routeGeometry(42);

    expect(geometry, hasLength(3));
    // Real coordinates, not the raw Web Mercator input — confirms the
    // inverse projection actually ran.
    expect(geometry.first.longitude, closeTo(11.0, 0.1));
  });

  test('routeGeometry rejects a relation with no usable geometry', () async {
    final body = jsonEncode({
      'route': {'main': [], 'appendices': []},
    });
    final client = WaymarkedTrailsClient(
      httpClient: _FakeClient((_) => body),
    );

    expect(client.routeGeometry(42), throwsA(isA<StateError>()));
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.bodyFor);

  final String Function(Uri uri) bodyFor;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = bodyFor(request.url);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}
