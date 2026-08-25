import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';

/// Resolves the visual downstream order of an OSM waterway.
///
/// This is deliberately a rendering concern: it never changes routing
/// topology or claims that a stream is safe to cross. OSM way order is used as
/// the fallback, while an explicit flow-direction tag can reverse it.
abstract final class WaterwayFlowResolver {
  static List<T> ordered<T>(LineFeature feature, List<T> points) {
    if (feature.kind != MapFeatureKind.waterway || points.length < 2) {
      return points;
    }
    if (feature.metadata.flowDirection == 'backward') {
      return points.reversed.toList(growable: false);
    }
    if (feature.metadata.flowDirection == 'forward') return points;

    // OSM way direction is not guaranteed to follow the downstream flow.
    // Without an explicit flow tag we must not pretend to know the river's
    // elevation, but we can still make the visual phase stable across cache
    // refreshes and neighbouring Overpass cells. Node references are the
    // only topology-safe tie breaker; geographic proximity is deliberately
    // not used here.
    final nodeIds = feature.nodeIds;
    if (nodeIds.length >= 2 && nodeIds.first.compareTo(nodeIds.last) > 0) {
      return points.reversed.toList(growable: false);
    }
    return points;
  }

  static bool isWaterway(LineFeature feature) =>
      feature.kind == MapFeatureKind.waterway &&
      feature.metadata.waterwayTag != null;
}
