import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/overpass_query_builder.dart';
import 'package:wildbit/domain/entities/geo_bounds.dart';

void main() {
  test('requests hiking POIs as nodes, ways and relations', () {
    final query = OverpassQueryBuilder.forBounds(
      const GeoBounds(
        southWest: LatLng(46, 11),
        northEast: LatLng(46.01, 11.01),
      ),
    );

    expect(query, contains('node["tourism"="alpine_hut"]'));
    expect(query, isNot(contains('way["tourism"="alpine_hut"]')));
    expect(query, contains('out body geom;'));
    expect(
      query,
      contains('highway"~"^(path|footway|track|steps|bridleway|via_ferrata)'),
    );
    expect(query, contains('way["ford"]'));
    expect(query, contains('way["barrier"~"^(fence|wall|hedge|retaining_wall'));
    expect(query, contains('node["ford"]'));
    expect(
      query,
      contains('node["barrier"~"^(gate|bollard|stile|turnstile)\$"]'),
    );
    expect(
      query,
      contains('relation["type"="route"]["route"~"^(hiking|foot)\$"]'),
    );
    expect(query, contains('out body;'));

    final structures = OverpassQueryBuilder.structuresForBounds(
      const GeoBounds(
        southWest: LatLng(46, 11),
        northEast: LatLng(46.01, 11.01),
      ),
    );
    expect(structures, contains('way["building"]'));
    expect(structures, contains('way["tourism"="alpine_hut"]'));
    expect(structures, contains('relation["tourism"="alpine_hut"]'));
    expect(structures, contains('way["tourism"="camp_site"]'));
    expect(structures, contains('relation["amenity"="parking"]'));
  });
}
