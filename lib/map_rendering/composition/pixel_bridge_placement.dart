import 'dart:ui';

/// Screen-space placement of a bridge over a projected water polygon.
///
/// The OSM bridge way gives us an axis, but its artwork must terminate on the
/// two shores, not at arbitrary way-node or sprite coordinates. This helper
/// intersects that axis with the polygon and adds a small land-side margin
/// for the bridge caps.
class PixelBridgePlacement {
  const PixelBridgePlacement({required this.start, required this.end});

  final Offset start;
  final Offset end;

  double get length => (end - start).distance;

  double distanceTo(Offset point) {
    final segment = end - start;
    final squaredLength = segment.dx * segment.dx + segment.dy * segment.dy;
    if (squaredLength <= .000001) return (point - start).distance;
    final fromStart = point - start;
    final projection =
        (fromStart.dx * segment.dx + fromStart.dy * segment.dy) / squaredLength;
    final closest = start + segment * projection.clamp(0.0, 1.0);
    return (point - closest).distance;
  }

  static PixelBridgePlacement? fromWaterPolygon({
    required List<Offset> polygon,
    List<List<Offset>> holes = const [],
    required Offset center,
    required Offset direction,
    double shoreMargin = 4,
    double? maximumAxisGap,
  }) {
    if (polygon.length < 3 || direction.distance < .001) return null;
    final axis = direction / direction.distance;
    final intersections = <double>[
      ..._intersections(polygon, center, axis),
      for (final hole in holes) ..._intersections(hole, center, axis),
    ]..sort();
    if (intersections.length < 2) return null;

    final unique = <double>[];
    for (final value in intersections) {
      if (unique.isEmpty || (value - unique.last).abs() > .01) {
        unique.add(value);
      }
    }
    final intervals = <({double start, double end})>[];
    for (var index = 0; index + 1 < unique.length; index++) {
      final first = unique[index];
      final last = unique[index + 1];
      if (last - first < .05) continue;
      final sample = center + axis * ((first + last) / 2);
      if (_insideWater(sample, polygon, holes)) {
        intervals.add((start: first, end: last));
      }
    }
    if (intervals.isEmpty) return null;
    final nearbyIntervals = maximumAxisGap == null
        ? intervals
        : intervals
              .where(
                (candidate) =>
                    candidate.start <= maximumAxisGap &&
                    candidate.end >= -maximumAxisGap,
              )
              .toList(growable: false);
    if (nearbyIntervals.isEmpty) return null;
    // Prefer the interval containing the bridge way's geographic midpoint.
    // If OSM gives a midpoint just outside a shore, use the nearest interval
    // rather than accidentally spanning a second bend of a concave lake.
    final interval = nearbyIntervals.firstWhere(
      (candidate) => candidate.start <= 0 && candidate.end >= 0,
      orElse: () => nearbyIntervals.reduce(
        (first, second) =>
            first.start.abs() + first.end.abs() <
                second.start.abs() + second.end.abs()
            ? first
            : second,
      ),
    );
    final first = interval.start;
    final last = interval.end;
    return PixelBridgePlacement(
      start: center + axis * (first - shoreMargin),
      end: center + axis * (last + shoreMargin),
    );
  }

  static List<double> _intersections(
    List<Offset> polygon,
    Offset center,
    Offset axis,
  ) {
    final intersections = <double>[];
    for (var index = 0; index < polygon.length; index++) {
      final a = polygon[index];
      final b = polygon[(index + 1) % polygon.length];
      final edge = b - a;
      final denominator = _cross(axis, edge);
      if (denominator.abs() < .0001) continue;
      final fromCenter = a - center;
      final t = _cross(fromCenter, edge) / denominator;
      final u = _cross(fromCenter, axis) / denominator;
      if (u >= -.0001 && u <= 1.0001 && t.isFinite) {
        intersections.add(t);
      }
    }
    return intersections;
  }

  static bool _insideWater(
    Offset point,
    List<Offset> polygon,
    List<List<Offset>> holes,
  ) {
    if (!_contains(polygon, point)) return false;
    return !holes.any((hole) => _contains(hole, point));
  }

  static bool _contains(List<Offset> polygon, Offset point) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final a = polygon[index];
      final b = polygon[previous];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crosses) continue;
      final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < x) inside = !inside;
    }
    return inside;
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
}
