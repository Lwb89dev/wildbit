import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/data/osm/feature_cache_codec.dart';
import 'package:wildbit/data/osm/overpass_parser.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('parses a multipolygon relation as one area with a hole', () {
    final collection = OverpassParser.parse({
      'elements': [
        {
          'type': 'way',
          'id': 10,
          'tags': {'natural': 'water'},
          'geometry': [
            {'lat': 0, 'lon': 0},
            {'lat': 0, 'lon': 2},
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
              ],
            },
            {
              'type': 'way',
              'ref': 11,
              'role': 'outer',
              'geometry': [
                {'lat': 2, 'lon': 2},
                {'lat': 2, 'lon': 0},
                {'lat': 0, 'lon': 0},
              ],
            },
            {
              'type': 'way',
              'ref': 12,
              'role': 'outer',
              'geometry': [
                {'lat': 0, 'lon': 2},
                {'lat': 2, 'lon': 2},
              ],
            },
            {
              'type': 'way',
              'ref': 13,
              'role': 'inner',
              'geometry': [
                {'lat': .5, 'lon': .5},
                {'lat': 1.5, 'lon': .5},
                {'lat': 1.5, 'lon': 1.5},
                {'lat': .5, 'lon': 1.5},
                {'lat': .5, 'lon': .5},
              ],
            },
          ],
        },
      ],
    });

    expect(collection.areas, hasLength(1));
    expect(collection.areas.single.kind, MapFeatureKind.water);
    expect(collection.areas.single.sourceId, 'relation-99-0');
    expect(collection.areas.single.holes, hasLength(1));
  });

  test('keeps multipolygon holes in the geographic cache', () {
    const features = MapFeatureCollection(
      areas: [
        AreaFeature(
          kind: MapFeatureKind.water,
          ring: [LatLng(0, 0), LatLng(0, 2), LatLng(2, 2), LatLng(2, 0)],
          holes: [
            [
              LatLng(.5, .5),
              LatLng(.5, 1.5),
              LatLng(1.5, 1.5),
              LatLng(1.5, .5),
            ],
          ],
        ),
      ],
      lines: [],
      pois: [],
    );
    final decoded = FeatureCacheCodec.decode(
      FeatureCacheCodec.encode(features),
    );
    expect(decoded.areas.single.holes, hasLength(1));
    expect(decoded.areas.single.holes.single, hasLength(4));
  });
}
