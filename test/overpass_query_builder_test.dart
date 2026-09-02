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
    expect(query, contains('node["ford"]'));
    expect(query, isNot(contains('barrier')));
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
    expect(structures, contains('out body geom 240;'));
    expect(structures, contains('way["tourism"="alpine_hut"]'));
    expect(structures, contains('relation["tourism"="alpine_hut"]'));
    expect(structures, contains('way["tourism"="camp_site"]'));
    expect(structures, contains('relation["amenity"="parking"]'));

    final hikingContext = OverpassQueryBuilder.structuresForBounds(
      const GeoBounds(
        southWest: LatLng(46, 11),
        northEast: LatLng(46.01, 11.01),
      ),
      includeBuildings: false,
    );
    expect(hikingContext, isNot(contains('way["building"]')));
    expect(hikingContext, isNot(contains('out body geom 240;')));
    expect(hikingContext, contains('way["tourism"="alpine_hut"]'));

    final trees = OverpassQueryBuilder.treesForBounds(
      const GeoBounds(
        southWest: LatLng(46, 11),
        northEast: LatLng(46.01, 11.01),
      ),
    );
    expect(trees, contains('node["natural"="tree"]'));
    expect(trees, contains('out body 700;'));
  });
}
