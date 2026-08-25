import 'package:latlong2/latlong.dart';

import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';
import 'waterway_flow_resolver.dart';

/// A continuous paint stroke assembled from one or more OSM waterway ways.
///
/// A stroke is a rendering primitive only: it never replaces the individual
/// OSM ways used by routing, access checks or cache identity.
class WaterwayRenderStroke {
  const WaterwayRenderStroke({required this.feature, required this.points});

  final LineFeature feature;
  final List<LatLng> points;
}

/// Joins adjacent waterway ways at shared OSM endpoint nodes.
///
/// OSM commonly splits a river into many short ways. Painting every way as an
/// independent animated rectangle creates phase seams and tiny mud gaps at
/// joins. This composer merges only degree-two chains. Junctions (degree > 2)
/// remain separate branches, so no downstream direction or topology is
/// invented. Ways without a complete node sequence are returned unchanged.
abstract final class WaterwayNetworkComposer {
  static List<WaterwayRenderStroke> compose(Iterable<LineFeature> source) {
    final features = [
      for (final feature in source)
        if (feature.points.length >= 2 &&
            feature.kind == MapFeatureKind.waterway)
          feature,
    ];
    final endpointDegree = <String, int>{};
    final eligible = <LineFeature>[];
    for (final feature in features) {
      if (!_hasCompleteTopology(feature)) continue;
      eligible.add(feature);
      endpointDegree.update(
        feature.nodeIds.first,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      endpointDegree.update(
        feature.nodeIds.last,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    // Start chains at network endpoints before visiting degree-two segments.
    // Overpass response order is unspecified; without this stable ordering a
    // middle way could consume only the downstream half of a chain.
    features.sort((first, second) {
      int endpointPriority(LineFeature feature) {
        if (!_hasCompleteTopology(feature)) return 2;
        final firstDegree = endpointDegree[feature.nodeIds.first] ?? 0;
        final lastDegree = endpointDegree[feature.nodeIds.last] ?? 0;
        return (firstDegree == 2 ? 1 : 0) + (lastDegree == 2 ? 1 : 0);
      }

      return endpointPriority(first).compareTo(endpointPriority(second));
    });
    final indexByFeature = <LineFeature, int>{
      for (var index = 0; index < features.length; index++)
        features[index]: index,
    };
    final visited = <int>{};
    final result = <WaterwayRenderStroke>[];

    for (final feature in features) {
      final index = indexByFeature[feature]!;
      if (visited.contains(index)) continue;
      if (!_hasCompleteTopology(feature)) {
        visited.add(index);
        result.add(
          WaterwayRenderStroke(
            feature: feature,
            points: List.unmodifiable(
              WaterwayFlowResolver.ordered(feature, feature.points),
            ),
          ),
        );
        continue;
      }
      final chain = _buildChain(
        feature,
        index,
        features,
        eligible,
        indexByFeature,
        endpointDegree,
        visited,
      );
      result.add(chain);
    }
    return List.unmodifiable(result);
  }

  static WaterwayRenderStroke _buildChain(
    LineFeature start,
    int startIndex,
    List<LineFeature> all,
    List<LineFeature> eligible,
    Map<LineFeature, int> indexByFeature,
    Map<String, int> endpointDegree,
    Set<int> visited,
  ) {
    var feature = start;
    var orientedPoints = [
      ...WaterwayFlowResolver.ordered(feature, feature.points),
    ];
    var orientedNodes = _orientedNodes(feature);

    // For untagged ways prefer beginning at a network endpoint. This makes a
    // whole branch stable even when Overpass returns its first way reversed.
    if (feature.metadata.flowDirection == null &&
        endpointDegree[orientedNodes.first] == 2 &&
        endpointDegree[orientedNodes.last] != 2) {
      orientedPoints = orientedPoints.reversed.toList();
      orientedNodes = orientedNodes.reversed.toList();
    }

    visited.add(startIndex);
    final points = <LatLng>[...orientedPoints];
    var currentNode = orientedNodes.last;
    while (endpointDegree[currentNode] == 2) {
      final nextIndex = _nextIndex(
        currentNode,
        feature,
        eligible,
        indexByFeature,
        visited,
      );
      if (nextIndex == null) break;
      final next = all[nextIndex];
      var nextPoints = WaterwayFlowResolver.ordered(next, next.points);
      var nextNodes = _orientedNodes(next);
      if (nextNodes.last == currentNode && nextNodes.first != currentNode) {
        nextPoints = nextPoints.reversed.toList();
        nextNodes = nextNodes.reversed.toList();
      }
      if (nextNodes.first != currentNode) break;
      points.addAll(nextPoints.skip(1));
      visited.add(nextIndex);
      feature = next;
      currentNode = nextNodes.last;
    }
    return WaterwayRenderStroke(
      feature: feature,
      points: List.unmodifiable(points),
    );
  }

  static int? _nextIndex(
    String node,
    LineFeature current,
    List<LineFeature> eligible,
    Map<LineFeature, int> indexByFeature,
    Set<int> visited,
  ) {
    for (final candidate in eligible) {
      final index = indexByFeature[candidate];
      if (index == null) continue;
      if (visited.contains(index) || candidate == current) continue;
      if (!_compatible(current, candidate)) continue;
      if (candidate.nodeIds.first == node || candidate.nodeIds.last == node) {
        return index;
      }
    }
    return null;
  }

  static bool _compatible(LineFeature first, LineFeature second) {
    return first.metadata.waterwayTag == second.metadata.waterwayTag &&
        first.metadata.flowDirection == second.metadata.flowDirection;
  }

  static bool _hasCompleteTopology(LineFeature feature) {
    return feature.nodeIds.length == feature.points.length &&
        feature.nodeIds.length >= 2 &&
        feature.nodeIds.every((id) => id.isNotEmpty);
  }

  static List<String> _orientedNodes(LineFeature feature) {
    final nodes = List<String>.from(feature.nodeIds);
    if (feature.metadata.flowDirection == 'backward') {
      return nodes.reversed.toList();
    }
    if (feature.metadata.flowDirection == 'forward') return nodes;
    if (nodes.first.compareTo(nodes.last) > 0) return nodes.reversed.toList();
    return nodes;
  }
}
