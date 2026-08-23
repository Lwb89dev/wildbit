import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/routing/route_chain_validator.dart';
import 'package:wildbit/domain/routing/route_topology_graph.dart';

RouteTopologySegment _segment(String start, String end, int index) {
  final line = LineFeature(
    kind: MapFeatureKind.trail,
    points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
    nodeIds: [start, end],
    metadata: RouteMetadata(osmWayId: 'way-$index'),
  );
  return RouteTopologySegment(
    wayId: 'way-$index',
    startNodeId: start,
    endNodeId: end,
    line: line,
    segmentIndex: 0,
  );
}

void main() {
  test('accepts an explicitly node-connected chain in either direction', () {
    final result = RouteChainValidator.validate([
      _segment('1', '2', 1),
      _segment('3', '2', 2),
      _segment('3', '4', 3),
    ]);

    expect(result.status, RouteChainStatus.continuous);
    expect(result.isContinuous, isTrue);
  });

  test('rejects adjacent segments with no shared OSM node', () {
    final result = RouteChainValidator.validate([
      _segment('1', '2', 1),
      _segment('3', '4', 2),
    ]);

    expect(result.status, RouteChainStatus.discontinuous);
    expect(result.breakAtSegmentIndex, 1);
  });

  test('does not accept automatic repeated sections', () {
    final repeated = _segment('1', '2', 1);
    final result = RouteChainValidator.validate([repeated, repeated]);

    expect(result.status, RouteChainStatus.incomplete);
    expect(result.reasons.single, contains('ripetuto'));
  });
}
