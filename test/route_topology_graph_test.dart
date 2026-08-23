import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/routing/route_topology_graph.dart';

LineFeature _line({
  required String wayId,
  required List<String> nodeIds,
  required List<LatLng> points,
}) {
  return LineFeature(
    kind: MapFeatureKind.trail,
    points: points,
    nodeIds: nodeIds,
    metadata: RouteMetadata(osmWayId: wayId),
  );
}

void main() {
  test('connects ways only where they share the same OSM node ID', () {
    final first = _line(
      wayId: '10',
      nodeIds: const ['1', '2'],
      points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
    );
    final second = _line(
      wayId: '11',
      nodeIds: const ['2', '3'],
      points: const [LatLng(46.001, 11.001), LatLng(46.002, 11.002)],
    );

    final graph = RouteTopologyBuilder.build([first, second]);

    expect(graph.segments, hasLength(2));
    expect(graph.segmentsAtNode['2'], hasLength(2));
    expect(graph.hasExplicitConnection('1', '2'), isTrue);
    expect(graph.hasExplicitConnection('1', '3'), isFalse);
    expect(graph.issues, isEmpty);
    expect(graph.verifiedWayCount, 2);
  });

  test('does not join coordinates that are nearby but have different IDs', () {
    final first = _line(
      wayId: '12',
      nodeIds: const ['10', '11'],
      points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
    );
    final second = _line(
      wayId: '13',
      nodeIds: const ['12', '13'],
      points: const [LatLng(46.00100001, 11.00100001), LatLng(46.002, 11.002)],
    );

    final graph = RouteTopologyBuilder.build([first, second]);

    expect(graph.segmentsAtNode['11'], hasLength(1));
    expect(graph.segmentsAtNode.containsKey('12'), isTrue);
    expect(graph.hasExplicitConnection('11', '12'), isFalse);
  });

  test('excludes a way when geometry and node references disagree', () {
    final graph = RouteTopologyBuilder.build([
      _line(
        wayId: '14',
        nodeIds: const ['20', '21', '22'],
        points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
      ),
    ]);

    expect(graph.segments, isEmpty);
    expect(graph.excludedWayCount, 1);
    expect(graph.verifiedWayCount, 0);
    expect(
      graph.issues.single.kind,
      RouteTopologyIssueKind.geometryNodeCountMismatch,
    );
  });
}
