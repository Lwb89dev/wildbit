import '../entities/line_feature.dart';

/// A verified, directed piece of an OSM way between two adjacent OSM nodes.
///
/// It deliberately stores references rather than inventing joins from nearby
/// coordinates. This is topology for validation, not a routing result.
class RouteTopologySegment {
  const RouteTopologySegment({
    required this.wayId,
    required this.startNodeId,
    required this.endNodeId,
    required this.line,
    required this.segmentIndex,
  });

  final String wayId;
  final String startNodeId;
  final String endNodeId;
  final LineFeature line;
  final int segmentIndex;
}

/// A diagnostic reason for a way intentionally excluded from topology.
enum RouteTopologyIssueKind { missingNodeReferences, geometryNodeCountMismatch }

class RouteTopologyIssue {
  const RouteTopologyIssue({required this.wayId, required this.kind});

  final String wayId;
  final RouteTopologyIssueKind kind;
}

/// A graph made solely of explicit OSM node references.
///
/// [segmentsAtNode] has entries only for node IDs emitted by Overpass. The
/// graph does not snap, simplify, or join lines whose coordinates merely look
/// close. It must not be used to propose a hiking route yet.
class RouteTopologyGraph {
  const RouteTopologyGraph._({
    required this.segments,
    required this.segmentsAtNode,
    required this.issues,
    required this.verifiedWayIds,
  });

  final List<RouteTopologySegment> segments;
  final Map<String, List<RouteTopologySegment>> segmentsAtNode;
  final List<RouteTopologyIssue> issues;

  /// Ways for which node references and geometry passed the strict topology
  /// import check. This says nothing about access, condition, or safety.
  final Set<String> verifiedWayIds;

  int get verifiedWayCount => verifiedWayIds.length;
  int get excludedWayCount => issues.length;

  bool hasExplicitConnection(String firstNodeId, String secondNodeId) {
    return segmentsAtNode[firstNodeId]?.any(
          (segment) =>
              (segment.startNodeId == firstNodeId &&
                  segment.endNodeId == secondNodeId) ||
              (segment.startNodeId == secondNodeId &&
                  segment.endNodeId == firstNodeId),
        ) ??
        false;
  }
}

/// Builds a conservative OSM topology graph from raw way node references.
abstract final class RouteTopologyBuilder {
  static RouteTopologyGraph build(Iterable<LineFeature> lines) {
    final segments = <RouteTopologySegment>[];
    final segmentsAtNode = <String, List<RouteTopologySegment>>{};
    final issues = <RouteTopologyIssue>[];
    final verifiedWayIds = <String>{};

    for (final entry in lines.indexed) {
      final index = entry.$1;
      final line = entry.$2;
      final wayId = line.metadata.osmWayId ?? 'unidentified-way-$index';

      if (line.nodeIds.length < 2) {
        issues.add(
          RouteTopologyIssue(
            wayId: wayId,
            kind: RouteTopologyIssueKind.missingNodeReferences,
          ),
        );
        continue;
      }
      // `out geom` must preserve the one-to-one correspondence with the way's
      // node list. If it does not, exclude the entire way instead of guessing.
      if (line.nodeIds.length != line.points.length) {
        issues.add(
          RouteTopologyIssue(
            wayId: wayId,
            kind: RouteTopologyIssueKind.geometryNodeCountMismatch,
          ),
        );
        continue;
      }
      verifiedWayIds.add(wayId);

      for (
        var nodeIndex = 0;
        nodeIndex < line.nodeIds.length - 1;
        nodeIndex++
      ) {
        final startNodeId = line.nodeIds[nodeIndex];
        final endNodeId = line.nodeIds[nodeIndex + 1];
        if (startNodeId == endNodeId) continue;
        final segment = RouteTopologySegment(
          wayId: wayId,
          startNodeId: startNodeId,
          endNodeId: endNodeId,
          line: line,
          segmentIndex: nodeIndex,
        );
        segments.add(segment);
        (segmentsAtNode[startNodeId] ??= []).add(segment);
        (segmentsAtNode[endNodeId] ??= []).add(segment);
      }
    }

    return RouteTopologyGraph._(
      segments: List.unmodifiable(segments),
      segmentsAtNode: Map<String, List<RouteTopologySegment>>.unmodifiable({
        for (final entry in segmentsAtNode.entries)
          entry.key: List<RouteTopologySegment>.unmodifiable(entry.value),
      }),
      issues: List.unmodifiable(issues),
      verifiedWayIds: Set.unmodifiable(verifiedWayIds),
    );
  }
}
