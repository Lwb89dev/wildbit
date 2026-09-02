import '../../domain/entities/line_feature.dart';
import 'package:latlong2/latlong.dart';

import 'geographic_ring_topology.dart';

/// A directed chain of coastline ways assembled through exact OSM node IDs.
///
/// The order is kept exactly as OSM supplies it: land is on the left and sea
/// on the right. No coordinate snapping is performed.
class CoastlineChain {
  const CoastlineChain({
    required this.nodeIds,
    required this.points,
    required this.wayIds,
  });

  final List<String> nodeIds;
  final List<LatLng> points;
  final List<String> wayIds;

  bool get isClosed => nodeIds.length > 2 && nodeIds.first == nodeIds.last;
}

enum CoastlineTopologyIssueKind {
  missingNodeReferences,
  geometryNodeCountMismatch,
  sharedNodeGeometryMismatch,
  degenerateGeometry,
  ambiguousContinuation,
  invalidClosedRing,
}

class CoastlineTopologyIssue {
  const CoastlineTopologyIssue({required this.wayId, required this.kind});

  final String wayId;
  final CoastlineTopologyIssueKind kind;
}

class CoastlineTopology {
  const CoastlineTopology({required this.chains, required this.issues});

  final List<CoastlineChain> chains;
  final List<CoastlineTopologyIssue> issues;
}

/// Reassembles directed OSM coastline pieces across cache-cell boundaries.
///
/// A join is accepted only when the end node of one way is exactly the start
/// node of the next. Branches are left unjoined and reported: guessing which
/// coastline branch is seawards would produce a wrong land/sea fill.
abstract final class CoastlineTopologyComposer {
  static CoastlineTopology compose(Iterable<LineFeature> lines) {
    final valid = <_MutableChain>[];
    final issues = <CoastlineTopologyIssue>[];
    final seenWayIds = <String>{};
    var fallbackId = 0;
    for (final line in lines) {
      final wayId =
          line.metadata.osmWayId ?? 'unidentified-coast-$fallbackId++';
      if (!seenWayIds.add(wayId)) {
        // Neighbouring cache cells can contain the same way. Duplicate
        // geometry would otherwise create ambiguous joins and double paint.
        continue;
      }
      if (line.nodeIds.length < 2) {
        issues.add(
          CoastlineTopologyIssue(
            wayId: wayId,
            kind: CoastlineTopologyIssueKind.missingNodeReferences,
          ),
        );
        continue;
      }
      if (line.nodeIds.length != line.points.length) {
        issues.add(
          CoastlineTopologyIssue(
            wayId: wayId,
            kind: CoastlineTopologyIssueKind.geometryNodeCountMismatch,
          ),
        );
        continue;
      }
      final candidate = _MutableChain.fromLine(line, wayId);
      if (candidate.nodeIds.length < 2) {
        issues.add(
          CoastlineTopologyIssue(
            wayId: wayId,
            kind: CoastlineTopologyIssueKind.degenerateGeometry,
          ),
        );
        continue;
      }
      if (candidate.isClosed && !_validClosedRing(candidate)) {
        issues.add(
          CoastlineTopologyIssue(
            wayId: wayId,
            kind: CoastlineTopologyIssueKind.invalidClosedRing,
          ),
        );
        continue;
      }
      valid.add(candidate);
    }

    final remaining = List<_MutableChain>.from(valid);
    // Index endpoints once. A global coastline can contain thousands of OSM
    // ways; scanning every remaining way for every join turns composition
    // into an avoidable quadratic operation.
    final byFirst = <String, List<_MutableChain>>{};
    final byLast = <String, List<_MutableChain>>{};
    for (final chain in remaining) {
      (byFirst[chain.firstNodeId] ??= []).add(chain);
      (byLast[chain.lastNodeId] ??= []).add(chain);
    }
    final available = remaining.toSet();
    final chains = <CoastlineChain>[];
    while (remaining.isNotEmpty) {
      final chain = remaining.removeAt(0);
      available.remove(chain);
      var extended = true;
      while (extended && !chain.isClosed) {
        extended = false;
        final next = (byFirst[chain.lastNodeId] ?? const <_MutableChain>[])
            .where(available.contains)
            .toList(growable: false);
        if (next.length == 1) {
          if (chain.canAppend(next.single)) {
            chain.append(next.single);
            remaining.remove(next.single);
            available.remove(next.single);
            extended = true;
          } else {
            issues.add(
              CoastlineTopologyIssue(
                wayId: next.single.wayIds.first,
                kind: CoastlineTopologyIssueKind.sharedNodeGeometryMismatch,
              ),
            );
          }
        } else if (next.length > 1) {
          issues.add(
            CoastlineTopologyIssue(
              wayId: chain.wayIds.last,
              kind: CoastlineTopologyIssueKind.ambiguousContinuation,
            ),
          );
        }
        if (extended) continue;

        final previous = (byLast[chain.firstNodeId] ?? const <_MutableChain>[])
            .where(available.contains)
            .toList(growable: false);
        if (previous.length == 1) {
          if (chain.canPrepend(previous.single)) {
            chain.prepend(previous.single);
            remaining.remove(previous.single);
            available.remove(previous.single);
            extended = true;
          } else {
            issues.add(
              CoastlineTopologyIssue(
                wayId: previous.single.wayIds.last,
                kind: CoastlineTopologyIssueKind.sharedNodeGeometryMismatch,
              ),
            );
          }
        } else if (previous.length > 1) {
          issues.add(
            CoastlineTopologyIssue(
              wayId: chain.wayIds.first,
              kind: CoastlineTopologyIssueKind.ambiguousContinuation,
            ),
          );
        }
      }
      if (chain.isClosed && !_validClosedRing(chain)) {
        issues.add(
          CoastlineTopologyIssue(
            wayId: chain.wayIds.join(','),
            kind: CoastlineTopologyIssueKind.invalidClosedRing,
          ),
        );
      } else {
        chains.add(chain.freeze());
      }
    }
    return CoastlineTopology(
      chains: List.unmodifiable(chains),
      issues: List.unmodifiable(issues),
    );
  }

  static bool _validClosedRing(_MutableChain chain) {
    if (!chain.isClosed || chain.points.length < 4) return false;
    final nodes = chain.nodeIds.take(chain.nodeIds.length - 1).toList();
    final points = chain.points.take(chain.points.length - 1).toList();
    return nodes.length >= 3 &&
        nodes.toSet().length == nodes.length &&
        !GeographicRingTopology.hasRepeatedVertex(points) &&
        !GeographicRingTopology.selfIntersects(points) &&
        GeographicRingTopology.area(points) >= 1e-12;
  }
}

class _MutableChain {
  _MutableChain({
    required this.nodeIds,
    required this.points,
    required this.wayIds,
  });

  factory _MutableChain.fromLine(LineFeature line, String wayId) =>
      _MutableChain._normalized(line, wayId);

  factory _MutableChain._normalized(LineFeature line, String wayId) {
    final nodes = <String>[];
    final points = <LatLng>[];
    for (var i = 0; i < line.nodeIds.length; i++) {
      final node = line.nodeIds[i];
      if (nodes.isNotEmpty && nodes.last == node) continue;
      nodes.add(node);
      points.add(line.points[i]);
    }
    return _MutableChain(nodeIds: nodes, points: points, wayIds: [wayId]);
  }

  final List<String> nodeIds;
  final List<LatLng> points;
  final List<String> wayIds;

  String get firstNodeId => nodeIds.first;
  String get lastNodeId => nodeIds.last;
  bool get isClosed => nodeIds.length > 2 && firstNodeId == lastNodeId;

  bool canAppend(_MutableChain next) =>
      lastNodeId == next.firstNodeId &&
      GeographicRingTopology.sameCoordinate(points.last, next.points.first);

  bool canPrepend(_MutableChain previous) =>
      previous.lastNodeId == firstNodeId &&
      GeographicRingTopology.sameCoordinate(previous.points.last, points.first);

  void append(_MutableChain next) {
    nodeIds.addAll(next.nodeIds.skip(1));
    points.addAll(next.points.skip(1));
    wayIds.addAll(next.wayIds);
  }

  void prepend(_MutableChain previous) {
    nodeIds.insertAll(0, previous.nodeIds.take(previous.nodeIds.length - 1));
    points.insertAll(0, previous.points.take(previous.points.length - 1));
    wayIds.insertAll(0, previous.wayIds);
  }

  CoastlineChain freeze() => CoastlineChain(
    nodeIds: List.unmodifiable(nodeIds),
    points: List.unmodifiable(points),
    wayIds: List.unmodifiable(wayIds),
  );
}
