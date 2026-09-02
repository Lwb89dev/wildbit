import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/poi.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';
import 'package:wildbit/map_rendering/performance/map_scene_metrics.dart';

void main() {
  test('counts geometry classes without changing source features', () {
    final metrics = MapSceneMetrics.fromFeatures(
      MapFeatureCollection(
        areas: const [
          AreaFeature(
            kind: MapFeatureKind.water,
            ring: [LatLng(45, 9), LatLng(45, 9.001), LatLng(45.001, 9.001)],
            holes: [
              [LatLng(45, 9), LatLng(45, 9.0001), LatLng(45.0001, 9)],
            ],
          ),
          AreaFeature(
            kind: MapFeatureKind.forest,
            ring: [LatLng(45, 9), LatLng(45, 9.001), LatLng(45.001, 9.001)],
          ),
        ],
        lines: const [
          LineFeature(
            kind: MapFeatureKind.trail,
            points: [LatLng(45, 9), LatLng(45.001, 9.001)],
          ),
        ],
        pois: const [
          Poi(
            id: 'tree-1',
            name: 'Albero',
            position: LatLng(45, 9),
            type: PoiType.tree,
          ),
        ],
      ),
    );

    expect(metrics.areaCount, 2);
    expect(metrics.waterAreas, 1);
    expect(metrics.forestAreas, 1);
    expect(metrics.lineCount, 1);
    expect(metrics.trails, 1);
    expect(metrics.trees, 1);
    expect(metrics.areaVertices, 9);
    expect(metrics.lineVertices, 2);
    expect(metrics.loadBand, 'leggera');
  });

  test('classifies pathological responses as dense', () {
    final metrics = MapSceneMetrics(
      areaCount: 100,
      lineCount: 300,
      poiCount: 300,
      areaVertices: 12000,
      lineVertices: 20000,
      waterAreas: 2,
      forestAreas: 10,
      buildings: 80,
      trails: 100,
      roads: 120,
      trees: 200,
    );
    expect(metrics.loadBand, 'densa');
  });
}
