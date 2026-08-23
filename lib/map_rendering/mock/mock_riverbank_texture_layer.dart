import 'package:flutter/material.dart';
import '../composition/pixel_water_polygon_layer.dart';
import '../composition/water_edge_composer.dart';
import 'mock_valley_water_geometry.dart';

/// Pixel-art water boundary pass for the prototype river.
///
/// The important part here is that every feature is attached to the water
/// polygon's edge. It is not randomly scattered on the meadow; the later OSM
/// compositor will supply this same boundary from each water geometry.
class MockRiverbankTextureLayer extends StatelessWidget {
  const MockRiverbankTextureLayer({super.key});

  @override
  Widget build(BuildContext context) => const PixelWaterPolygonLayer(
    polygon: MockValleyWaterGeometry.riverPolygon,
    material: WaterEdgeMaterial.grass,
    chunkSeed: 741,
    edgeSpacing: 32,
  );
}
