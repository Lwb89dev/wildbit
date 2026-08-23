import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/feature_cache_codec.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';

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
}
