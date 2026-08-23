import 'route_topology_graph.dart';

/// Result of checking an already selected sequence of OSM topology segments.
///
/// This validator never searches the graph and never creates a route. It only
/// proves (or fails to prove) that the supplied sequence can be traversed
/// through explicit shared OSM node IDs.
enum RouteChainStatus { incomplete, discontinuous, continuous }

class RouteChainValidation {
  const RouteChainValidation({
    required this.status,
    required this.reasons,
    this.breakAtSegmentIndex,
  });

  final RouteChainStatus status;
  final List<String> reasons;

  /// Index of the first supplied segment that could not continue the chain.
  final int? breakAtSegmentIndex;

  bool get isContinuous => status == RouteChainStatus.continuous;
}

abstract final class RouteChainValidator {
  /// Validates [segments] in their supplied order.
  ///
  /// Each segment may be traversed in either direction, but an adjacent pair
  /// must meet at the same OSM node ID. Repeated segment references are kept
  /// out of automatic proposals: a loop or deliberate backtrack needs human
  /// review instead of being silently accepted.
  static RouteChainValidation validate(
    Iterable<RouteTopologySegment> segments,
  ) {
    final chain = segments.toList(growable: false);
    if (chain.isEmpty) {
      return const RouteChainValidation(
        status: RouteChainStatus.incomplete,
        reasons: ['nessun tratto topologico fornito'],
      );
    }

    final seenSegments = <String>{};
    var possibleEnds = <String>{chain.first.startNodeId, chain.first.endNodeId};
    seenSegments.add(_segmentKey(chain.first));

    for (var index = 1; index < chain.length; index++) {
      final segment = chain[index];
      if (!seenSegments.add(_segmentKey(segment))) {
        return RouteChainValidation(
          status: RouteChainStatus.incomplete,
          reasons: ['tratto OSM ripetuto: richiede revisione umana'],
          breakAtSegmentIndex: index,
        );
      }

      final nextEnds = <String>{};
      if (possibleEnds.contains(segment.startNodeId)) {
        nextEnds.add(segment.endNodeId);
      }
      if (possibleEnds.contains(segment.endNodeId)) {
        nextEnds.add(segment.startNodeId);
      }
      if (nextEnds.isEmpty) {
        return RouteChainValidation(
          status: RouteChainStatus.discontinuous,
          reasons: ['tratti non connessi da un nodo OSM condiviso'],
          breakAtSegmentIndex: index,
        );
      }
      possibleEnds = nextEnds;
    }

    return const RouteChainValidation(
      status: RouteChainStatus.continuous,
      reasons: [],
    );
  }

  static String _segmentKey(RouteTopologySegment segment) =>
      '${segment.wayId}:${segment.segmentIndex}:'
      '${segment.startNodeId}:${segment.endNodeId}';
}
