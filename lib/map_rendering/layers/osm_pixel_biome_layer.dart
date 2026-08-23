import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/projected_texture_area_batch.dart';
import '../performance/map_rendering_budget.dart';

/// Ground-only land-cover pass for OSM forest and meadow polygons.
/// Tree sprites are rendered separately in one batched Canvas layer.
class OsmPixelBiomeLayer extends StatelessWidget {
  const OsmPixelBiomeLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final areas = features.areas.where(
      (area) =>
          (area.kind == MapFeatureKind.forest ||
              area.kind == MapFeatureKind.meadow ||
              area.kind == MapFeatureKind.park) &&
          MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds),
    ).toList(growable: false);
    if (areas.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: ProjectedTextureAreaBatch(
        camera: camera,
        areas: [
          for (final area in areas)
            ProjectedTextureAreaSpec(
              area: area,
              asset: area.kind == MapFeatureKind.forest
                  ? 'assets/map/mock/terrain/forest_floor.png'
                  : 'assets/map/mock/terrain/grass_2.png',
              fallbackColor: area.kind == MapFeatureKind.forest
                  ? const Color(0xFF315C45)
                  : const Color(0xFF9BB867),
            ),
        ],
      ),
    );
  }
}
