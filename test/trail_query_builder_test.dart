import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/trail_query_builder.dart';

void main() {
  const position = LatLng(46.07, 11.12);

  test('nearby Explore query requests only bare way segments', () {
    final query = TrailQueryBuilder.nearby(position: position, radiusKm: 12);

    // Curated hiking route relations come from WaymarkedTrailsClient
    // instead — this query must not duplicate them via Overpass.
    expect(query, isNot(contains('relation[')));
    expect(query, contains('way["highway"~'));
    expect(query, isNot(contains(r'\$')));
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
