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
    for (var index = 0; index < nodes.length; index++)
      LatLng(45.0 + index, 10.0 + index),
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
}
