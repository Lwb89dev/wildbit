import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/data/osm/feature_cache_codec.dart';
import 'package:wildbit/data/test_data/osm_replay_region.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';
import 'package:wildbit/map_rendering/performance/map_scene_metrics.dart';

void main() {
  test(
    'OSM replay passes raw response through production topology parsing',
    () {
      final water = osmReplayFeatures.areas.singleWhere(
        (area) => area.kind == MapFeatureKind.water,
      );
      final trail = osmReplayFeatures.lines.singleWhere(
        (line) => line.name == 'Sentiero del Lago',
      );

      expect(osmReplayFeatures.areas, hasLength(4));
      expect(water.sourceId, 'relation-2001-0');
      expect(water.holes, hasLength(1));
      expect(
        osmReplayFeatures.lines.where(
          (line) => line.kind == MapFeatureKind.waterway,
        ),
        hasLength(1),
      );
      expect(trail.metadata.hikingRoutes.single.ref, 'AV-17');
      expect(trail.metadata.sacScale, 'mountain_hiking');
      expect(
        osmReplayFeatures.pois.where((poi) => poi.type == PoiType.tree),
        hasLength(92),
      );
      expect(
        osmReplayFeatures.pois.where((poi) => poi.type == PoiType.shelter),
        hasLength(1),
      );
    },
  );

  test('OSM replay topology survives the offline feature cache', () {
    final restored = FeatureCacheCodec.decode(
      FeatureCacheCodec.encode(osmReplayFeatures),
    );
    final water = restored.areas.singleWhere(
      (area) => area.kind == MapFeatureKind.water,
    );

    expect(water.holes, hasLength(1));
    expect(restored.lines, hasLength(osmReplayFeatures.lines.length));
    expect(restored.pois, hasLength(osmReplayFeatures.pois.length));
  });

  test('OSM replay reports its source complexity before Canvas work', () {
    final metrics = MapSceneMetrics.fromFeatures(osmReplayFeatures);

    expect(metrics.areaCount, 4);
    expect(metrics.waterAreas, 1);
    expect(metrics.forestAreas, 1);
    expect(metrics.trails, 2);
    expect(metrics.roads, 1);
    expect(metrics.trees, 92);
    expect(metrics.totalVertices, greaterThan(30));
  });
}
