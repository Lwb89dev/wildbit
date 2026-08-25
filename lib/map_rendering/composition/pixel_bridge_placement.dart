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

  static PixelBridgePlacement? fromWaterPolygon({
    required List<Offset> polygon,
    required Offset center,
    required Offset direction,
    double shoreMargin = 4,
  }) {
    if (polygon.length < 3 || direction.distance < .001) return null;
    final axis = direction / direction.distance;
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
    if (intersections.length < 2) return null;
    intersections.sort();
    final first = intersections.first;
    final last = intersections.last;
    if (!first.isFinite || !last.isFinite || last - first < .05) return null;
    return PixelBridgePlacement(
      start: center + axis * (first - shoreMargin),
      end: center + axis * (last + shoreMargin),
    );
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
}
