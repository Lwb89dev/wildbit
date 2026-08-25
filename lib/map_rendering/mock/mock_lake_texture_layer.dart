import 'package:flutter/material.dart';

import '../composition/pixel_water_polygon_layer.dart';
import '../composition/water_edge_composer.dart';
import 'mock_valley_water_geometry.dart';

/// Closed lake basin for the interactive mock. Unlike the river it has no
/// flow direction, so its water pattern remains stationary while zooming.
class MockLakeTextureLayer extends StatelessWidget {
  const MockLakeTextureLayer({super.key});

  @override
  Widget build(BuildContext context) => const PixelWaterPolygonLayer(
    polygon: MockValleyWaterGeometry.lakePolygon,
    material: WaterEdgeMaterial.sand,
    chunkSeed: 913,
    edgeSpacing: 8,
    edgeScale: .75,
    maxEdgePlacements: 96,
  );
}
