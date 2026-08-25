import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/overpass_parser.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';

void main() {
  test('keeps a valid standalone way when its relation is incomplete', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 10,
          'tags': {'natural': 'water'},
          'geometry': [
            {'lat': 0, 'lon': 0},
            {'lat': 0, 'lon': 2},
            {'lat': 2, 'lon': 2},
            {'lat': 2, 'lon': 0},
            {'lat': 0, 'lon': 0},
          ],
        },
        {
          'type': 'relation',
          'id': 99,
          'tags': {'type': 'multipolygon', 'natural': 'water'},
          'members': [
            {
              'type': 'way',
              'ref': 10,
              'role': 'outer',
              'geometry': [
                {'lat': 0, 'lon': 0},
                {'lat': 0, 'lon': 2},
                {'lat': 2, 'lon': 2},
                {'lat': 2, 'lon': 0},
                {'lat': 0, 'lon': 0},
              ],
            },
            {
              'type': 'way',
              'ref': 11,
              'role': 'outer',
              'geometry': [
                {'lat': 5, 'lon': 5},
                {'lat': 5, 'lon': 6},
              ],
            },
          ],
        },
      ],
    });

    expect(collection.areas, hasLength(1));
    expect(collection.areas.single.kind, MapFeatureKind.water);
    expect(collection.areas.single.sourceId, '10');
    expect(collection.areas.single.ring.first, const LatLng(0, 0));
  });
}
