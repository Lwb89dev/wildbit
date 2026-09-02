import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/map_rendering/composition/geographic_ring_topology.dart';

void main() {
  const datelineRing = [
    LatLng(10, 179),
    LatLng(10, -179),
    LatLng(12, -179),
    LatLng(12, 179),
  ];

  test('contains points on both sides of the antimeridian', () {
    expect(
      GeographicRingTopology.contains(datelineRing, const LatLng(11, 179.5)),
      isTrue,
    );
    expect(
      GeographicRingTopology.contains(datelineRing, const LatLng(11, -179.5)),
      isTrue,
    );
    expect(
      GeographicRingTopology.contains(datelineRing, const LatLng(11, 170)),
      isFalse,
    );
  });

  test('computes local area instead of a world-spanning dateline area', () {
    expect(GeographicRingTopology.area(datelineRing), closeTo(4, 1e-9));
    expect(GeographicRingTopology.selfIntersects(datelineRing), isFalse);
  });
}
