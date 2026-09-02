import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Conservative topology predicates for geographic polygon rings.
///
/// Longitude is unwrapped before every planar operation, so a valid ring near
/// 180°E/180°W is treated as a small local polygon instead of a shape spanning
/// almost the entire world. These helpers only validate rendering geometry;
/// they never repair or invent missing OSM boundaries.
abstract final class GeographicRingTopology {
  static bool sameCoordinate(LatLng first, LatLng second) {
    final latitudeDelta = (first.latitude - second.latitude).abs();
    final longitudeDelta = _wrappedLongitudeDelta(
      first.longitude,
      second.longitude,
    );
    return latitudeDelta <= 1e-8 && longitudeDelta <= 1e-8;
  }

  static bool hasRepeatedVertex(List<LatLng> ring) {
    for (var first = 0; first < ring.length; first++) {
      for (var second = first + 1; second < ring.length; second++) {
        if (sameCoordinate(ring[first], ring[second])) return true;
      }
    }
    return false;
  }

  static double area(List<LatLng> ring) {
    final points = _unwrap(ring);
    if (points.length < 3) return 0;
    var sum = 0.0;
    for (var index = 0; index < points.length; index++) {
      final next = points[(index + 1) % points.length];
      sum += points[index].x * next.y - next.x * points[index].y;
    }
    return sum.abs() / 2;
  }

  static bool contains(List<LatLng> ring, LatLng point) {
    final polygon = _unwrap(ring, referenceLongitude: point.longitude);
    if (polygon.length < 3) return false;
    final sample = _PlanarPoint(
      _longitudeNear(point.longitude, polygon.first.x),
      point.latitude,
    );
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final a = polygon[index];
      final b = polygon[previous];
      if (_pointOnSegment(a, b, sample)) return true;
      final crosses = (a.y > sample.y) != (b.y > sample.y);
      if (!crosses) continue;
      final x = (b.x - a.x) * (sample.y - a.y) / (b.y - a.y) + a.x;
      if (sample.x < x) inside = !inside;
    }
    return inside;
  }

  static bool selfIntersects(List<LatLng> ring) {
    final points = _unwrap(ring);
    if (points.length < 4) return false;
    for (var first = 0; first < points.length; first++) {
      final firstEnd = (first + 1) % points.length;
      for (var second = first + 1; second < points.length; second++) {
        final secondEnd = (second + 1) % points.length;
        if (first == second || firstEnd == second || secondEnd == first) {
          continue;
        }
        if (_segmentsIntersect(
          points[first],
          points[firstEnd],
          points[second],
          points[secondEnd],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns true for crossings and boundary touches between two rings.
  static bool ringsIntersect(List<LatLng> first, List<LatLng> second) {
    if (first.length < 2 || second.length < 2) return false;
    final reference = first.first.longitude;
    final a = _unwrap(first, referenceLongitude: reference);
    final b = _unwrap(second, referenceLongitude: reference);
    for (var firstIndex = 0; firstIndex < a.length; firstIndex++) {
      final firstEnd = (firstIndex + 1) % a.length;
      for (var secondIndex = 0; secondIndex < b.length; secondIndex++) {
        final secondEnd = (secondIndex + 1) % b.length;
        if (_segmentsIntersect(
          a[firstIndex],
          a[firstEnd],
          b[secondIndex],
          b[secondEnd],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static List<_PlanarPoint> _unwrap(
    List<LatLng> ring, {
    double? referenceLongitude,
  }) {
    if (ring.isEmpty) return const [];
    final points = <_PlanarPoint>[];
    var previous = referenceLongitude == null
        ? ring.first.longitude
        : _longitudeNear(ring.first.longitude, referenceLongitude);
    points.add(_PlanarPoint(previous, ring.first.latitude));
    for (final point in ring.skip(1)) {
      final longitude = _longitudeNear(point.longitude, previous);
      points.add(_PlanarPoint(longitude, point.latitude));
      previous = longitude;
    }
    return points;
  }

  static double _longitudeNear(double longitude, double reference) {
    var result = longitude;
    while (result - reference > 180) {
      result -= 360;
    }
    while (result - reference < -180) {
      result += 360;
    }
    return result;
  }

  static double _wrappedLongitudeDelta(double first, double second) {
    final raw = (first - second).abs() % 360;
    return math.min(raw, 360 - raw);
  }

  static bool _segmentsIntersect(
    _PlanarPoint a,
    _PlanarPoint b,
    _PlanarPoint c,
    _PlanarPoint d,
  ) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    const epsilon = 1e-14;
    final proper =
        (abC > epsilon && abD < -epsilon || abC < -epsilon && abD > epsilon) &&
        (cdA > epsilon && cdB < -epsilon || cdA < -epsilon && cdB > epsilon);
    if (proper) return true;
    return abC.abs() <= epsilon && _pointOnSegment(a, b, c) ||
        abD.abs() <= epsilon && _pointOnSegment(a, b, d) ||
        cdA.abs() <= epsilon && _pointOnSegment(c, d, a) ||
        cdB.abs() <= epsilon && _pointOnSegment(c, d, b);
  }

  static double _orientation(_PlanarPoint a, _PlanarPoint b, _PlanarPoint c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

  static bool _pointOnSegment(
    _PlanarPoint a,
    _PlanarPoint b,
    _PlanarPoint point,
  ) {
    const epsilon = 1e-12;
    if (_orientation(a, b, point).abs() > epsilon) return false;
    return point.x >= math.min(a.x, b.x) - epsilon &&
        point.x <= math.max(a.x, b.x) + epsilon &&
        point.y >= math.min(a.y, b.y) - epsilon &&
        point.y <= math.max(a.y, b.y) + epsilon;
  }
}

class _PlanarPoint {
  const _PlanarPoint(this.x, this.y);

  final double x;
  final double y;
}
