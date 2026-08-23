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
    Offset(256, 256),
    Offset(256, 0),
  ];
}
