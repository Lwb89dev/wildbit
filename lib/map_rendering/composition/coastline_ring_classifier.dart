import 'dart:ui';

enum CoastlineRingRole { outerIsland, nestedWaterHole }

class CoastlineRing {
  const CoastlineRing({
    required this.points,
    required this.depth,
    required this.role,
  });

  final List<Offset> points;
  final int depth;
  final CoastlineRingRole role;
}

/// Classifies closed projected coastline rings by containment depth.
///
/// Even depth means land/island; odd depth means a nested water hole. The
/// classifier does not infer safety or navigation semantics and intentionally
/// leaves self-intersecting rings to the topology validator upstream.
abstract final class CoastlineRingClassifier {
  static List<CoastlineRing> classify(List<List<Offset>> rings) {
    final normalized = <_ScreenRing>[];
    for (final ring in rings) {
      final points = _normalize(ring);
      if (points == null) continue;
      // A broad interior sample of an outer island can itself fall inside a
      // nested lake/island and would over-count containment depth. Once ring
      // intersections have been excluded, a boundary vertex cannot lie on a
      // different ring unless the topology is ambiguous; it is therefore the
      // stable sample for parent/child classification. The scanline sample is
      // still required to prove that the projected ring has usable interior.
      if (_interiorSample(points) != null) {
        normalized.add(_ScreenRing(points, points.first));
      }
    }
    // Intersecting/touching closed coastlines have ambiguous land/sea parity.
    // Omitting them is safer than flooding an island or painting sea as land.
    final ambiguous = <int>{};
    for (var first = 0; first < normalized.length; first++) {
      for (var second = first + 1; second < normalized.length; second++) {
        if (_ringsIntersect(
          normalized[first].points,
          normalized[second].points,
        )) {
          ambiguous.add(first);
          ambiguous.add(second);
        }
      }
    }
    final safe = [
      for (final entry in normalized.indexed)
        if (!ambiguous.contains(entry.$1)) entry.$2,
    ];
    final result = <CoastlineRing>[];
    for (var index = 0; index < safe.length; index++) {
      final ring = safe[index];
      var depth = 0;
      for (var other = 0; other < safe.length; other++) {
        if (other == index) continue;
        if (_contains(safe[other].points, ring.sample)) depth++;
      }
      result.add(
        CoastlineRing(
          points: ring.points,
          depth: depth,
          role: depth.isEven
              ? CoastlineRingRole.outerIsland
              : CoastlineRingRole.nestedWaterHole,
        ),
      );
    }
    result.sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      return depth != 0 ? depth : _area(b.points).compareTo(_area(a.points));
    });
    return List.unmodifiable(result);
  }

  static List<Offset>? _normalize(List<Offset> source) {
    final points = <Offset>[];
    for (final point in source) {
      if (points.isEmpty || (point - points.last).distance > .01) {
        points.add(point);
      }
    }
    if (points.length > 1 && (points.first - points.last).distance <= .01) {
      points.removeLast();
    }
    if (points.length < 3 || _area(points) < 1e-4) return null;
    for (var first = 0; first < points.length; first++) {
      for (var second = first + 1; second < points.length; second++) {
        if ((points[first] - points[second]).distance <= .01) return null;
      }
    }
    if (_selfIntersects(points)) return null;
    return List.unmodifiable(points);
  }

  /// Finds a point guaranteed to lie in a valid concave ring by intersecting
  /// several horizontal scanlines and selecting the widest interior span.
  static Offset? _interiorSample(List<Offset> polygon) {
    var top = polygon.first.dy;
    var bottom = top;
    for (final point in polygon.skip(1)) {
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }
    final height = bottom - top;
    if (height <= .001) return null;
    Offset? best;
    var bestWidth = 0.0;
    for (final fraction in const [.23, .37, .5, .63, .77]) {
      final y = top + height * fraction;
      final intersections = <double>[];
      for (var index = 0; index < polygon.length; index++) {
        final a = polygon[index];
        final b = polygon[(index + 1) % polygon.length];
        if ((a.dy > y) == (b.dy > y)) continue;
        intersections.add(a.dx + (y - a.dy) * (b.dx - a.dx) / (b.dy - a.dy));
      }
      intersections.sort();
      for (var index = 0; index + 1 < intersections.length; index += 2) {
        final width = intersections[index + 1] - intersections[index];
        if (width <= bestWidth) continue;
        final candidate = Offset(
          (intersections[index] + intersections[index + 1]) / 2,
          y,
        );
        if (_contains(polygon, candidate)) {
          best = candidate;
          bestWidth = width;
        }
      }
    }
    return best;
  }

  static bool _contains(List<Offset> polygon, Offset point) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crosses) continue;
      final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < x) inside = !inside;
    }
    return inside;
  }

  static double _area(List<Offset> polygon) {
    var sum = 0.0;
    for (var index = 0; index < polygon.length; index++) {
      final next = polygon[(index + 1) % polygon.length];
      sum += polygon[index].dx * next.dy - next.dx * polygon[index].dy;
    }
    return sum.abs() / 2;
  }

  static bool _selfIntersects(List<Offset> polygon) {
    for (var first = 0; first < polygon.length; first++) {
      final firstEnd = (first + 1) % polygon.length;
      for (var second = first + 1; second < polygon.length; second++) {
        final secondEnd = (second + 1) % polygon.length;
        if (first == second || firstEnd == second || secondEnd == first) {
          continue;
        }
        if (_segmentsIntersect(
          polygon[first],
          polygon[firstEnd],
          polygon[second],
          polygon[secondEnd],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _ringsIntersect(List<Offset> first, List<Offset> second) {
    for (var a = 0; a < first.length; a++) {
      for (var b = 0; b < second.length; b++) {
        if (_segmentsIntersect(
          first[a],
          first[(a + 1) % first.length],
          second[b],
          second[(b + 1) % second.length],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final abC = _cross(b - a, c - a);
    final abD = _cross(b - a, d - a);
    final cdA = _cross(d - c, a - c);
    final cdB = _cross(d - c, b - c);
    const epsilon = 1e-6;
    final proper =
        (abC > epsilon && abD < -epsilon || abC < -epsilon && abD > epsilon) &&
        (cdA > epsilon && cdB < -epsilon || cdA < -epsilon && cdB > epsilon);
    if (proper) return true;
    return abC.abs() <= epsilon && _onSegment(a, b, c) ||
        abD.abs() <= epsilon && _onSegment(a, b, d) ||
        cdA.abs() <= epsilon && _onSegment(c, d, a) ||
        cdB.abs() <= epsilon && _onSegment(c, d, b);
  }

  static bool _onSegment(Offset a, Offset b, Offset point) {
    const epsilon = .01;
    return point.dx >= (a.dx < b.dx ? a.dx : b.dx) - epsilon &&
        point.dx <= (a.dx > b.dx ? a.dx : b.dx) + epsilon &&
        point.dy >= (a.dy < b.dy ? a.dy : b.dy) - epsilon &&
        point.dy <= (a.dy > b.dy ? a.dy : b.dy) + epsilon;
  }

  static double _cross(Offset first, Offset second) =>
      first.dx * second.dy - first.dy * second.dx;
}

class _ScreenRing {
  const _ScreenRing(this.points, this.sample);

  final List<Offset> points;
  final Offset sample;
}
