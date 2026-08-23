import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/feature_cache_codec.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/poi.dart';
import 'package:wildbit/domain/entities/poi_metadata.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';

void main() {
  test('persists ordered OSM node references for topology', () {
    final source = MapFeatureCollection(
      areas: const [],
      pois: const [],
      lines: [
        LineFeature(
          kind: MapFeatureKind.trail,
          points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
          nodeIds: const ['1', '2'],
          metadata: const RouteMetadata(osmWayId: '1'),
        ),
      ],
    );

    final restored = FeatureCacheCodec.decode(FeatureCacheCodec.encode(source));

    expect(restored.lines.single.nodeIds, ['1', '2']);
  });

  test('persists OSM identities for filled polygons', () {
    const json =
        '{"areas":[{"kind":"water","ring":[[46,11],[46.1,11.1]],"sourceId":"77"}],"lines":[],"pois":[]}';

    expect(FeatureCacheCodec.decode(json).areas.single.sourceId, '77');
  });

  test('marks caches without a format version as stale', () {
    expect(FeatureCacheCodec.isCurrentFormat('{"areas":[]}'), isFalse);
    expect(
      FeatureCacheCodec.isCurrentFormat(
        FeatureCacheCodec.encode(
          const MapFeatureCollection(areas: [], lines: [], pois: []),
        ),
      ),
      isTrue,
    );
  });

  test('persists safety-relevant POI metadata', () {
    const source = MapFeatureCollection(
      areas: [],
      lines: [],
      pois: [
        Poi(
          id: 'osm-node-42',
          name: 'Fonte',
          type: PoiType.waterSource,
          position: LatLng(46, 11),
          metadata: PoiMetadata(
            elevationMeters: 1234,
            access: 'permissive',
            drinkingWater: false,
            operatorName: 'Comune',
            openingHours: '24/7',
          ),
        ),
      ],
    );

    final restored = FeatureCacheCodec.decode(FeatureCacheCodec.encode(source));
    final metadata = restored.pois.single.metadata;

    expect(metadata.elevationMeters, 1234);
    expect(metadata.access, 'permissive');
    expect(metadata.drinkingWater, isFalse);
    expect(metadata.operatorName, 'Comune');
    expect(metadata.openingHours, '24/7');
  });
}
