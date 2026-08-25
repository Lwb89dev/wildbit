import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/waterway_network_composer.dart';

LineFeature _way({
  required List<String> nodes,
  required List<LatLng> points,
  String tag = 'stream',
}) => LineFeature(
  kind: MapFeatureKind.waterway,
  points: points,
  nodeIds: nodes,
  metadata: RouteMetadata(waterwayTag: tag),
);

void main() {
  test('joins a split degree-two waterway at its shared OSM node', () {
    final result = WaterwayNetworkComposer.compose([
      _way(
        nodes: const ['node-c', 'node-b'],
        points: const [LatLng(45.02, 9.02), LatLng(45.01, 9.01)],
      ),
      _way(
        nodes: const ['node-a', 'node-b'],
        points: const [LatLng(45, 9), LatLng(45.01, 9.01)],
      ),
      _way(
        nodes: const ['node-d', 'node-c'],
        points: const [LatLng(45.03, 9.03), LatLng(45.02, 9.02)],
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.points, const [
      LatLng(45, 9),
      LatLng(45.01, 9.01),
      LatLng(45.02, 9.02),
      LatLng(45.03, 9.03),
    ]);
  });

  test('keeps a confluence as separate branches', () {
    final result = WaterwayNetworkComposer.compose([
      _way(
        nodes: const ['node-a', 'node-junction'],
        points: const [LatLng(45, 9), LatLng(45.01, 9.01)],
      ),
      _way(
        nodes: const ['node-junction', 'node-b'],
        points: const [LatLng(45.01, 9.01), LatLng(45.02, 9.02)],
      ),
      _way(
        nodes: const ['node-junction', 'node-c'],
        points: const [LatLng(45.01, 9.01), LatLng(45.02, 9)],
      ),
    ]);

    expect(result, hasLength(3));
    expect(result.every((stroke) => stroke.points.length == 2), isTrue);
  });

  test('does not merge ways without a complete node sequence', () {
    final result = WaterwayNetworkComposer.compose([
      _way(nodes: const [], points: const [LatLng(45, 9), LatLng(45.01, 9.01)]),
      _way(
        nodes: const ['node-a', 'node-b'],
        points: const [LatLng(45.01, 9.01), LatLng(45.02, 9.02)],
      ),
    ]);

    expect(result, hasLength(2));
  });
}
