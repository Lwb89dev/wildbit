import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';

/// Immutable source-geometry snapshot used by debug/profile diagnostics.
class MapSceneMetrics {
  const MapSceneMetrics({
    required this.areaCount,
    required this.lineCount,
    required this.poiCount,
    required this.areaVertices,
    required this.lineVertices,
    required this.waterAreas,
    required this.forestAreas,
    required this.buildings,
    required this.trails,
    required this.roads,
    required this.trees,
  });

  factory MapSceneMetrics.fromFeatures(MapFeatureCollection features) {
    var areaVertices = 0;
    var waterAreas = 0;
    var forestAreas = 0;
    var buildings = 0;
    for (final area in features.areas) {
      areaVertices += area.ring.length;
      for (final hole in area.holes) {
        areaVertices += hole.length;
      }
      switch (area.kind) {
        case MapFeatureKind.water:
          waterAreas++;
        case MapFeatureKind.forest:
        case MapFeatureKind.park:
          forestAreas++;
        case MapFeatureKind.building:
          buildings++;
        default:
          break;
      }
    }
    var lineVertices = 0;
    var trails = 0;
    var roads = 0;
    for (final line in features.lines) {
      lineVertices += line.points.length;
      if (line.kind == MapFeatureKind.trail) trails++;
      if (line.kind == MapFeatureKind.road) roads++;
    }
    final trees = features.pois.where((poi) => poi.type == PoiType.tree).length;
    return MapSceneMetrics(
      areaCount: features.areas.length,
      lineCount: features.lines.length,
      poiCount: features.pois.length,
      areaVertices: areaVertices,
      lineVertices: lineVertices,
      waterAreas: waterAreas,
      forestAreas: forestAreas,
      buildings: buildings,
      trails: trails,
      roads: roads,
      trees: trees,
    );
  }

  const MapSceneMetrics.empty()
    : areaCount = 0,
      lineCount = 0,
      poiCount = 0,
      areaVertices = 0,
      lineVertices = 0,
      waterAreas = 0,
      forestAreas = 0,
      buildings = 0,
      trails = 0,
      roads = 0,
      trees = 0;

  final int areaCount;
  final int lineCount;
  final int poiCount;
  final int areaVertices;
  final int lineVertices;
  final int waterAreas;
  final int forestAreas;
  final int buildings;
  final int trails;
  final int roads;
  final int trees;

  int get totalVertices => areaVertices + lineVertices;

  String get loadBand {
    final weight =
        areaCount * 2 + lineCount + poiCount * 2 + totalVertices ~/ 24;
    if (weight < 500) return 'leggera';
    if (weight < 1500) return 'media';
    return 'densa';
  }

  @override
  bool operator ==(Object other) =>
      other is MapSceneMetrics &&
      areaCount == other.areaCount &&
      lineCount == other.lineCount &&
      poiCount == other.poiCount &&
      areaVertices == other.areaVertices &&
      lineVertices == other.lineVertices &&
      waterAreas == other.waterAreas &&
      forestAreas == other.forestAreas &&
      buildings == other.buildings &&
      trails == other.trails &&
      roads == other.roads &&
      trees == other.trees;

  @override
  int get hashCode => Object.hash(
    areaCount,
    lineCount,
    poiCount,
    areaVertices,
    lineVertices,
    waterAreas,
    forestAreas,
    buildings,
    trails,
    roads,
    trees,
  );
}
