import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/waterway_flow_resolver.dart';

void main() {
  test('reverses only an explicitly backward waterway', () {
    final line = LineFeature(
      kind: MapFeatureKind.waterway,
      points: const [LatLng(46, 11), LatLng(46.1, 11.1)],
      metadata: const RouteMetadata(
        waterwayTag: 'river',
        flowDirection: 'backward',
      ),
    );

    expect(
      WaterwayFlowResolver.ordered(line, line.points).first,
      line.points.last,
    );
  });

  test('does not invent a direction for a non-waterway line', () {
    final line = LineFeature(
      kind: MapFeatureKind.trail,
      points: const [LatLng(46, 11), LatLng(46.1, 11.1)],
      metadata: const RouteMetadata(flowDirection: 'backward'),
    );

    expect(WaterwayFlowResolver.ordered(line, line.points), line.points);
  });

  test('uses stable OSM endpoint order when flow direction is unknown', () {
    final line = LineFeature(
      kind: MapFeatureKind.waterway,
      points: const [LatLng(46, 11), LatLng(46.1, 11.1)],
      nodeIds: const ['node-z', 'node-a'],
      metadata: const RouteMetadata(waterwayTag: 'stream'),
    );

    expect(
      WaterwayFlowResolver.ordered(line, line.points).first,
      line.points.last,
    );
  });

  test('does not override an explicitly forward direction', () {
    final line = LineFeature(
      kind: MapFeatureKind.waterway,
      points: const [LatLng(46, 11), LatLng(46.1, 11.1)],
      nodeIds: const ['node-z', 'node-a'],
      metadata: const RouteMetadata(
        waterwayTag: 'river',
        flowDirection: 'forward',
      ),
    );

    expect(WaterwayFlowResolver.ordered(line, line.points), line.points);
  });
}
