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
    material: WaterEdgeMaterial.mud,
    chunkSeed: 741,
    // The mock river descends through the valley; animation must follow its
    // longitudinal axis instead of sliding across its width.
    flowDirection: Offset(0, 1),
    // Mud tiles provide the bank transition; the geometric outline is only a
    // subtle containment hint and is no longer the shoreline artwork itself.
    edgeSpacing: 8,
    edgeScale: .65,
    maxEdgePlacements: 96,
  );
}
