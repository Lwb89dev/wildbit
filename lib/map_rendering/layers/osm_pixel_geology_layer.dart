import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/projected_texture_area_batch.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel terrain pass for OSM rock and snow polygons.
///
/// It uses native authored bitmap textures and an OSM polygon clip; it does
/// not sample, recolour, or pixelate a conventional basemap.
class OsmPixelGeologyLayer extends StatelessWidget {
  const OsmPixelGeologyLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final areas = features.areas
        .where(
          (area) =>
              (area.kind == MapFeatureKind.mountainRock ||
                  area.kind == MapFeatureKind.snow) &&
              MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds),
        )
        .toList(growable: false);
    if (areas.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: ProjectedTextureAreaBatch(
        camera: camera,
        areas: [
          for (final area in areas)
            ProjectedTextureAreaSpec(
              area: area,
              asset: area.kind == MapFeatureKind.snow
                  ? 'assets/map/mock/terrain/snow_base_1.png'
                  : 'assets/map/mock/terrain/rock_generated_1.png',
              fallbackColor: area.kind == MapFeatureKind.snow
                  ? const Color(0xFFF4F0E6)
                  : const Color(0xFF8D8173),
              borderColor: area.kind == MapFeatureKind.snow
                  ? const Color(0xFFB7C4BD)
                  : const Color(0xFF514B43),
              borderWidth:
                  .7 + .5 * ((camera.zoom - 9) / 5).clamp(0.0, 1.0),
            ),
        ],
      ),
    );
  }
}
