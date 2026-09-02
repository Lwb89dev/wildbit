import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/coastline_topology_composer.dart';

LineFeature _coast(String id, List<String> nodes) => LineFeature(
  kind: MapFeatureKind.coastline,
  nodeIds: nodes,
  points: [
    for (final node in nodes)
      switch (node) {
        '1' => const LatLng(45, 10),
        '2' => const LatLng(45, 11),
        '3' => const LatLng(46, 11),
        '4' => const LatLng(46, 10),
        _ => const LatLng(47, 12),
      },
  ],
  metadata: RouteMetadata(osmWayId: id),
);

void main() {
  test('joins directed coastline ways through their exact shared node', () {
    final topology = CoastlineTopologyComposer.compose([
      _coast('a', ['1', '2']),
      _coast('b', ['2', '3']),
    ]);

    expect(topology.chains, hasLength(1));
    expect(topology.chains.single.nodeIds, ['1', '2', '3']);
    expect(topology.chains.single.wayIds, ['a', 'b']);
  });

  test('joins directed ways independently of their download order', () {
    final topology = CoastlineTopologyComposer.compose([
      _coast('b', ['2', '3']),
      _coast('a', ['1', '2']),
    ]);

    expect(topology.chains, hasLength(1));
    expect(topology.chains.single.nodeIds, ['1', '2', '3']);
  });

  test('does not reverse or guess an invalid coastline continuation', () {
    final topology = CoastlineTopologyComposer.compose([
      _coast('a', ['1', '2']),
      _coast('b', ['3', '2']),
    ]);

    expect(topology.chains, hasLength(2));
  });

  test('recognises a closed coastline as an island ring', () {
    final topology = CoastlineTopologyComposer.compose([
      _coast('island-a', ['1', '2']),
      _coast('island-b', ['2', '3']),
      _coast('island-c', ['3', '1']),
    ]);

    expect(topology.chains.single.isClosed, isTrue);
  });

  test('rejects a closed coastline with a repeated interior node', () {
    final topology = CoastlineTopologyComposer.compose([
      _coast('degenerate', ['1', '2', '3', '2', '1']),
    ]);

    expect(topology.chains, isEmpty);
    expect(
      topology.issues.single.kind,
      CoastlineTopologyIssueKind.invalidClosedRing,
    );
  });

  test('rejects geometry that cannot be matched to OSM node references', () {
    final invalid = LineFeature(
      kind: MapFeatureKind.coastline,
      nodeIds: const ['1', '2', '3'],
      points: const [LatLng(45, 10), LatLng(46, 11)],
      metadata: const RouteMetadata(osmWayId: 'bad'),
    );
    final topology = CoastlineTopologyComposer.compose([invalid]);

    expect(topology.chains, isEmpty);
    expect(
      topology.issues.single.kind,
      CoastlineTopologyIssueKind.geometryNodeCountMismatch,
    );
  });

  test('rejects a joined closed ring that self-intersects', () {
    LineFeature segment(
      String id,
      String start,
      LatLng startPoint,
      String end,
      LatLng endPoint,
    ) => LineFeature(
      kind: MapFeatureKind.coastline,
      nodeIds: [start, end],
      points: [startPoint, endPoint],
      metadata: RouteMetadata(osmWayId: id),
    );

    final topology = CoastlineTopologyComposer.compose([
      segment('a', 'a', const LatLng(0, 0), 'b', const LatLng(1, 1)),
      segment('b', 'b', const LatLng(1, 1), 'c', const LatLng(0, 1)),
      segment('c', 'c', const LatLng(0, 1), 'd', const LatLng(1, 0)),
      segment('d', 'd', const LatLng(1, 0), 'a', const LatLng(0, 0)),
    ]);

    expect(topology.chains, isEmpty);
    expect(
      topology.issues.map((issue) => issue.kind),
      contains(CoastlineTopologyIssueKind.invalidClosedRing),
    );
  });

  test('does not join equal node IDs with conflicting coordinates', () {
    final topology = CoastlineTopologyComposer.compose([
      const LineFeature(
        kind: MapFeatureKind.coastline,
        nodeIds: ['a', 'shared'],
        points: [LatLng(45, 10), LatLng(45, 11)],
        metadata: RouteMetadata(osmWayId: 'a'),
      ),
      const LineFeature(
        kind: MapFeatureKind.coastline,
        nodeIds: ['shared', 'b'],
        points: [LatLng(45.1, 11), LatLng(46, 11)],
        metadata: RouteMetadata(osmWayId: 'b'),
      ),
    ]);

    expect(topology.chains, hasLength(2));
    expect(
      topology.issues.map((issue) => issue.kind),
      contains(CoastlineTopologyIssueKind.sharedNodeGeometryMismatch),
    );
  });
}
