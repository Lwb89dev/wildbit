import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';

/// Resolves the visual downstream order of an OSM waterway.
///
/// This is deliberately a rendering concern: it never changes routing
/// topology or claims that a stream is safe to cross. OSM way order is used as
/// the fallback, while an explicit flow-direction tag can reverse it.
abstract final class WaterwayFlowResolver {
  static List<T> ordered<T>(LineFeature feature, List<T> points) {
    if (feature.kind != MapFeatureKind.waterway ||
        feature.metadata.flowDirection != 'backward') {
      return points;
    }
    return points.reversed.toList(growable: false);
  }

  static bool isWaterway(LineFeature feature) =>
      feature.kind == MapFeatureKind.waterway &&
      feature.metadata.waterwayTag != null;
}
