import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/map_rendering/composition/osm_line_projector.dart';

void main() {
  test('recorded track paint simplification preserves exact endpoints', () {
    final source = [
      const LatLng(46, 11),
      const LatLng(46.000001, 11.000001),
      const LatLng(46.001, 11.001),
    ];
    final projected = OsmLineProjector.projectSimplifiedPoints(
      source,
      (point) => Offset(point.longitude * 100, point.latitude * 100),
      minimumDistancePixels: 2,
      maximumPoints: 32,
    );
    expect(projected.first, const Offset(1100, 4600));
    expect(projected.last.dx, closeTo(1100.1, 1e-6));
    expect(projected.last.dy, closeTo(4600.1, 1e-6));
  });
}
