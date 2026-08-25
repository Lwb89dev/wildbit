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
          'id': 803,
          'tags': {'barrier': 'fence'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
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
            'ref': '105',
            'tracktype': 'grade3',
            'ford': 'yes',
            'access:conditional': 'no @ (winter)',
            'opening_hours': 'May-Oct',
          },
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
          'nodes': [100, 101],
        },
      ],
    });

    final metadata = collection.lines
        .firstWhere((line) => line.metadata.osmWayId == '42')
        .metadata;
    expect(metadata.osmWayId, '42');
    expect(metadata.hasConfirmedBridge, isTrue);
    expect(metadata.widthMeters, .8);
    expect(metadata.sacScale, 'mountain_hiking');
    expect(metadata.trailVisibility, 'intermediate');
    expect(metadata.ref, '105');
    expect(metadata.highwayTag, 'path');
    expect(metadata.trackType, 'grade3');
    expect(metadata.fordTag, 'yes');
    expect(metadata.hasConditionalAccess, isTrue);
    expect(metadata.accessConditional, 'no @ (winter)');
    expect(metadata.openingHours, 'May-Oct');
    expect(
      collection.lines
          .firstWhere((line) => line.metadata.osmWayId == '42')
          .nodeIds,
      ['100', '101'],
    );
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

  test('enriches only exact way members from hiking route relations', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'relation',
          'id': 700,
          'tags': {
            'type': 'route',
            'route': 'hiking',
            'network': 'nwn',
            'ref': 'E5',
            'name': 'Sentiero Europeo E5',
          },
          'members': [
            {'type': 'way', 'ref': 42, 'role': ''},
            {'type': 'way', 'ref': 999, 'role': ''},
            {'type': 'node', 'ref': 123, 'role': 'guidepost'},
          ],
        },
        {
          'type': 'way',
          'id': 42,
          'tags': {'highway': 'path'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
        {
          'type': 'way',
          'id': 43,
          'tags': {'highway': 'path'},
          'geometry': [
            {'lat': 46.002, 'lon': 11.002},
            {'lat': 46.003, 'lon': 11.003},
          ],
        },
      ],
    });

    final mapped = collection.lines.first.metadata.hikingRoutes.single;
    expect(mapped.relationId, '700');
    expect(mapped.ref, 'E5');
    expect(mapped.name, 'Sentiero Europeo E5');
    expect(mapped.network, 'nwn');
    expect(collection.lines.last.metadata.hikingRoutes, isEmpty);
    expect(collection.lines, hasLength(2));
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
    expect(collection.pois[1].metadata.shelterType, 'wilderness_hut');
    expect(collection.pois[1].metadata.openingHours, 'Jun-Sep 08:00-20:00');
  });

  test('parses node guados and ignores retired barrier tags', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'node',
          'id': 801,
          'lat': 46.1,
          'lon': 11.1,
          'tags': {'ford': 'yes'},
        },
        {
          'type': 'node',
          'id': 802,
          'lat': 46.2,
          'lon': 11.2,
          'tags': {'barrier': 'gate'},
        },
        {
          'type': 'way',
          'id': 803,
          'tags': {'barrier': 'fence'},
          'geometry': [
            {'lat': 46.3, 'lon': 11.3},
            {'lat': 46.301, 'lon': 11.301},
          ],
          'nodes': [900, 901],
        },
      ],
    });

    expect(collection.lines, isEmpty);
    expect(collection.pois.map((poi) => poi.type), [PoiType.ford]);
    expect(collection.pois[0].name, 'Guado');
  });

  test('keeps a hut way as both building footprint and semantic POI', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 901,
          'tags': {
            'building': 'yes',
            'tourism': 'alpine_hut',
            'name': 'Rifugio Stella',
            'ele': '2010',
          },
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.0, 'lon': 11.002},
            {'lat': 46.002, 'lon': 11.002},
            {'lat': 46.002, 'lon': 11.0},
            {'lat': 46.0, 'lon': 11.0},
          ],
        },
      ],
    });

    expect(collection.areas, hasLength(1));
    expect(collection.areas.single.kind, MapFeatureKind.building);
    expect(collection.pois, hasLength(1));
    expect(collection.pois.single.id, 'osm-way-901');
    expect(collection.pois.single.type, PoiType.shelter);
    expect(collection.pois.single.name, 'Rifugio Stella');
    expect(collection.pois.single.position.latitude, closeTo(46.001, 1e-6));
    expect(collection.pois.single.position.longitude, closeTo(11.001, 1e-6));
    expect(collection.pois.single.metadata.elevationMeters, 2010);
    expect(collection.pois.single.metadata.shelterType, 'alpine_hut');
  });

  test('extracts a semantic POI from relation member geometry', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'relation',
          'id': 902,
          'tags': {'tourism': 'camp_site', 'name': 'Campo del Bosco'},
          'members': [
            {
              'type': 'way',
              'ref': 12,
              'role': 'outer',
              'geometry': [
                {'lat': 46.0, 'lon': 11.0},
                {'lat': 46.0, 'lon': 11.004},
                {'lat': 46.004, 'lon': 11.004},
                {'lat': 46.004, 'lon': 11.0},
                {'lat': 46.0, 'lon': 11.0},
              ],
            },
          ],
        },
      ],
    });

    expect(collection.pois, hasLength(1));
    expect(collection.pois.single.id, 'osm-relation-902');
    expect(collection.pois.single.type, PoiType.campsite);
    expect(collection.pois.single.position.latitude, closeTo(46.002, 1e-6));
    expect(collection.pois.single.position.longitude, closeTo(11.002, 1e-6));
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

  test('preserves explicit downstream direction for animated waterways', () {
    final line = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 46,
          'tags': {'waterway': 'river', 'flow_direction': 'backward'},
          'geometry': [
            {'lat': 46.0, 'lon': 11.0},
            {'lat': 46.001, 'lon': 11.001},
          ],
        },
      ],
    }).lines.single;

    expect(line.metadata.waterwayTag, 'river');
    expect(line.metadata.flowDirection, 'backward');
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
