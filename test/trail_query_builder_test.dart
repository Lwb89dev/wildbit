import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/trail_query_builder.dart';

void main() {
  const position = LatLng(46.07, 11.12);

  test('nearby Explore query accepts hiking routes without network tags', () {
    final query = TrailQueryBuilder.nearby(position: position, radiusKm: 12);

    expect(query, contains('relation["type"="route"]["route"~'));
    expect(query, contains(r'^(hiking|foot)$'));
    expect(query, isNot(contains(r'\$')));
    expect(query, isNot(contains('["network"~')));
    expect(query, contains('around:12000,46.07,11.12'));
  });

  test(
    'named Explore search matches both OSM name and CAI-like ref safely',
    () {
      final query = TrailQueryBuilder.nearby(
        position: position,
        radiusKm: 100,
        query: 'CAI "401"',
      );

      expect(query, contains('["name"~"CAI \\"401\\"",i]'));
      expect(query, contains('["ref"~"CAI \\"401\\"",i]'));
      expect(query, contains('around:100000,46.07,11.12'));
    },
  );
}
