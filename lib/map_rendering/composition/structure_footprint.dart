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
      final key =
          '${point.latitude.toStringAsFixed(8)}:'
          '${point.longitude.toStringAsFixed(8)}';
      if (!seen.add(key)) return null;
    }
    if (_selfIntersects(points)) return null;
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
      sum +=
          ring[index].longitude * ring[next].latitude -
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

  static bool _selfIntersects(List<LatLng> ring) {
    for (var first = 0; first < ring.length; first++) {
      final firstEnd = (first + 1) % ring.length;
      for (var second = first + 1; second < ring.length; second++) {
        final secondEnd = (second + 1) % ring.length;
        if (first == second || firstEnd == second || secondEnd == first) {
          continue;
        }
        if (_segmentsIntersect(
          ring[first],
          ring[firstEnd],
          ring[second],
          ring[secondEnd],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    const epsilon = 1e-14;
    final proper =
        (abC > epsilon && abD < -epsilon || abC < -epsilon && abD > epsilon) &&
        (cdA > epsilon && cdB < -epsilon || cdA < -epsilon && cdB > epsilon);
    if (proper) return true;
    return abC.abs() <= epsilon && _onSegment(a, b, c) ||
        abD.abs() <= epsilon && _onSegment(a, b, d) ||
        cdA.abs() <= epsilon && _onSegment(c, d, a) ||
        cdB.abs() <= epsilon && _onSegment(c, d, b);
  }

  static double _orientation(LatLng a, LatLng b, LatLng c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  static bool _onSegment(LatLng a, LatLng b, LatLng point) =>
      point.longitude >=
          (a.longitude < b.longitude ? a.longitude : b.longitude) - 1e-12 &&
      point.longitude <=
          (a.longitude > b.longitude ? a.longitude : b.longitude) + 1e-12 &&
      point.latitude >=
          (a.latitude < b.latitude ? a.latitude : b.latitude) - 1e-12 &&
      point.latitude <=
          (a.latitude > b.latitude ? a.latitude : b.latitude) + 1e-12;
}
