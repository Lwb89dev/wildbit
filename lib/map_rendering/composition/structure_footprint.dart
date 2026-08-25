import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geometry helpers shared by building, hut and POI structure renderers.
///
/// OSM ways can contain a repeated closing node, duplicate intermediate
/// nodes, or very small degenerate rings. These cases are rejected before
/// projection so a malformed footprint cannot create a large accidental
/// triangle on the map.
abstract final class StructureFootprint {
  static List<LatLng>? sanitize(Iterable<LatLng> source) {
    final points = <LatLng>[];
    for (final point in source) {
      if (points.isEmpty || !_same(points.last, point)) points.add(point);
    }
    if (points.length > 1 && _same(points.first, points.last)) {
      points.removeLast();
    }
    if (points.length < 3) return null;
    final seen = <String>{};
    for (final point in points) {
      final key = point.latitude.toStringAsFixed(8) +
          ':' +
          point.longitude.toStringAsFixed(8);
      if (!seen.add(key)) return null;
    }
    if (area(points).abs() < 1e-12) return null;
    return List.unmodifiable(points);
  }

  static LatLng centroid(List<LatLng> ring) {
    if (ring.isEmpty) return const LatLng(0, 0);
    var latitude = 0.0;
    var longitude = 0.0;
    for (final point in ring) {
      latitude += point.latitude;
      longitude += point.longitude;
    }
    return LatLng(latitude / ring.length, longitude / ring.length);
  }

  static double area(List<LatLng> ring) {
    if (ring.length < 3) return 0;
    var sum = 0.0;
    for (var index = 0; index < ring.length; index++) {
      final next = (index + 1) % ring.length;
      sum += ring[index].longitude * ring[next].latitude -
          ring[next].longitude * ring[index].latitude;
    }
    return sum / 2;
  }

  static double longestEdge(List<LatLng> ring) {
    var longest = 0.0;
    for (var index = 0; index < ring.length; index++) {
      final next = (index + 1) % ring.length;
      final dLat = ring[index].latitude - ring[next].latitude;
      final dLon = ring[index].longitude - ring[next].longitude;
      longest = math.max(longest, math.sqrt(dLat * dLat + dLon * dLon));
    }
    return longest;
  }

  static bool _same(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-10 &&
      (a.longitude - b.longitude).abs() < 1e-10;
}
