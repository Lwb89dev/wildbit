import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wildbit/data/osm/nominatim_client.dart';

void main() {
  test('search resolves the top match to a position', () async {
    final body = jsonEncode([
      {
        'lat': '44.4056',
        'lon': '8.9463',
        'display_name': 'Genova, Liguria, Italia',
      },
    ]);
    final client = NominatimClient(httpClient: _FakeClient(200, body));

    final place = await client.search('Genova');

    expect(place, isNotNull);
    expect(place!.position.latitude, closeTo(44.4056, 0.0001));
    expect(place.displayName, contains('Genova'));
  });

  test('search returns null for no matches', () async {
    final client = NominatimClient(httpClient: _FakeClient(200, '[]'));

    expect(await client.search('Nessunlandia'), isNull);
  });

  test('search returns null on a non-200 response instead of throwing', () async {
    final client = NominatimClient(httpClient: _FakeClient(503, ''));

    expect(await client.search('Genova'), isNull);
  });

  test('an empty query is never sent', () async {
    final fakeClient = _FakeClient(200, '[]');
    final client = NominatimClient(httpClient: fakeClient);

    expect(await client.search('   '), isNull);
    expect(fakeClient.calls, 0);
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.statusCode, this.body);

  final int statusCode;
  final String body;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}
