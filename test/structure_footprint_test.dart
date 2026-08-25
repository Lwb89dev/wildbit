import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/map_rendering/composition/structure_footprint.dart';

void main() {
  test('removes a closing node but rejects repeated interior nodes', () {
    final clean = StructureFootprint.sanitize(const [
      LatLng(46, 11),
      LatLng(46, 11.001),
      LatLng(46.001, 11.001),
      LatLng(46.001, 11),
      LatLng(46, 11),
    ]);
    expect(clean, hasLength(4));
    expect(
      StructureFootprint.sanitize(const [
        LatLng(46, 11),
        LatLng(46, 11.001),
        LatLng(46.001, 11.001),
        LatLng(46, 11.001),
      ]),
      isNull,
    );
  });

  test('computes a stable centroid and rejects degenerate rings', () {
    const ring = [
      LatLng(46, 11),
      LatLng(46, 11.002),
      LatLng(46.001, 11.002),
      LatLng(46.001, 11),
    ];
    expect(StructureFootprint.centroid(ring).latitude, closeTo(46.0005, 1e-8));
    expect(StructureFootprint.longestEdge(ring), greaterThan(0));
    expect(
      StructureFootprint.sanitize(const [
        LatLng(46, 11),
        LatLng(46, 11.001),
        LatLng(46, 11.002),
      ]),
      isNull,
    );
  });

  test('rejects a self-intersecting building footprint', () {
    expect(
      StructureFootprint.sanitize(const [
        LatLng(46, 11),
        LatLng(46.001, 11.001),
        LatLng(46, 11.001),
        LatLng(46.001, 11),
      ]),
      isNull,
    );
  });
}
