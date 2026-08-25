import 'dart:ui';

/// Example projected water geometry. Production code will supply this list
/// from a decoded OSM way/relation after map-to-logical-pixel projection.
abstract final class MockValleyWaterGeometry {
  static const riverPolygon = <Offset>[
    Offset(205, 0),
    Offset(193, 19),
    Offset(190, 38),
    Offset(210, 68),
    Offset(192, 101),
    Offset(176, 125),
    Offset(203, 161),
    Offset(192, 205),
    Offset(181, 228),
    Offset(178, 256),
    // Keep both banks inside the mock viewport.  The bridge at y≈123 can
    // therefore terminate on solid ground instead of disappearing into the
    // right-hand edge of the water polygon.
    Offset(232, 256),
    Offset(232, 0),
  ];

  /// A separate lake basin used by the interactive mock to exercise a closed
  /// water ring (and its shoreline) alongside the open river.
  static const lakePolygon = <Offset>[
    Offset(8, 177),
    Offset(24, 164),
    Offset(58, 166),
    Offset(86, 182),
    Offset(101, 209),
    Offset(93, 239),
    Offset(72, 253),
    Offset(8, 253),
  ];

  static bool containsWater(Offset point) =>
      _contains(riverPolygon, point) || _contains(lakePolygon, point);

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
}
