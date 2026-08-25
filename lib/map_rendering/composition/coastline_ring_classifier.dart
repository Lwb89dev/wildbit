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
    final result = <CoastlineRing>[];
    for (var index = 0; index < rings.length; index++) {
      final points = rings[index];
      if (points.length < 3) continue;
      final sample = points.first;
      var depth = 0;
      for (var other = 0; other < rings.length; other++) {
        if (other == index || rings[other].length < 3) continue;
        if (_contains(rings[other], sample)) depth++;
      }
      result.add(
        CoastlineRing(
          points: points,
          depth: depth,
          role: depth.isEven
              ? CoastlineRingRole.outerIsland
              : CoastlineRingRole.nestedWaterHole,
        ),
      );
    }
    result.sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      return depth != 0 ? depth : a.points.length.compareTo(b.points.length);
    });
    return List.unmodifiable(result);
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
}
