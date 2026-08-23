import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/data/osm/overpass_parser.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';

void main() {
  test('preserves route tags without treating unknown data as safe', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 42,
          'tags': {
            'highway': 'path',
            'bridge': 'yes',
            'bridge:structure': 'simple-suspension',
            'surface': 'wood',
            'width': '0.8 m',
            'sac_scale': 'mountain_hiking',
            'trail_visibility': 'intermediate',
            'access': 'permissive',
            'foot': 'yes',
          },
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
          'nodes': [100, 101],
        },
      ],
    });

    final metadata = collection.lines.single.metadata;
    expect(metadata.osmWayId, '42');
    expect(metadata.hasConfirmedBridge, isTrue);
    expect(metadata.widthMeters, .8);
    expect(metadata.sacScale, 'mountain_hiking');
    expect(metadata.trailVisibility, 'intermediate');
    expect(collection.lines.single.nodeIds, ['100', '101']);
  });

  test('does not guess ambiguous width or bridge state', () {
    final metadata = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 43,
          'tags': {
            'highway': 'path',
            'width': 'about 1 m',
            'bridge': 'unknown',
          },
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
      ],
    }).lines.single.metadata;

    expect(metadata.widthMeters, isNull);
    expect(metadata.hasConfirmedBridge, isFalse);
  });

  test('parses hiking guideposts and wilderness huts as explicit POIs', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'node',
          'id': 501,
          'lat': 46.1,
          'lon': 11.1,
          'tags': {
            'tourism': 'information',
            'information': 'guidepost',
            'ele': '1642 m',
            'access': 'permissive',
            'operator': 'SAT',
          },
        },
        {
          'type': 'node',
          'id': 502,
          'lat': 46.2,
          'lon': 11.2,
          'tags': {
            'tourism': 'wilderness_hut',
            'opening_hours': 'Jun-Sep 08:00-20:00',
          },
        },
      ],
    });

    expect(collection.pois[0].type, PoiType.guidepost);
    expect(collection.pois[0].name, 'Cartello escursionistico');
    expect(collection.pois[0].metadata.elevationMeters, 1642);
    expect(collection.pois[0].metadata.access, 'permissive');
    expect(collection.pois[0].metadata.operatorName, 'SAT');
    expect(collection.pois[1].type, PoiType.shelter);
    expect(collection.pois[1].name, 'Rifugio');
    expect(collection.pois[1].metadata.openingHours, 'Jun-Sep 08:00-20:00');
  });

  test('keeps a mapped stream as a waterway line, not a route', () {
    final line = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 44,
          'tags': {'waterway': 'stream'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
      ],
    }).lines.single;

    expect(line.kind.name, 'waterway');
    expect(line.metadata.osmWayId, '44');
  });

  test('keeps a coastline as directed geographic context, not a route', () {
    final line = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 45,
          'tags': {'natural': 'coastline'},
          'nodes': [1, 2],
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
      ],
    }).lines.single;

    expect(line.kind.name, 'coastline');
    expect(line.nodeIds, ['1', '2']);
  });

  test('keeps parks and individually mapped trees as visual context', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 46,
          'tags': {'leisure': 'park'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.0, 'lon': 11.001},
            {'lat': 46.001, 'lon': 11.001},
            {'lat': 46.0, 'lon': 11.0},
          ],
        },
        {
          'type': 'node',
          'id': 47,
          'lat': 46.0005,
          'lon': 11.0005,
          'tags': {'natural': 'tree'},
        },
      ],
    });

    expect(collection.areas.single.kind.name, 'park');
    expect(collection.pois.single.type.name, 'tree');
    expect(collection.pois.single.name, 'Albero');
  });

  test('keeps mapped buildings as a low-priority area', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 48,
          'tags': {'building': 'yes'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.0, 'lon': 11.001},
            {'lat': 46.001, 'lon': 11.001},
            {'lat': 46.0, 'lon': 11.0},
          ],
        },
      ],
    });

    expect(collection.areas.single.kind, MapFeatureKind.building);
  });
}
