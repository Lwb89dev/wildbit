import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../domain/entities/map_feature_collection.dart';
import 'hd_terrain_painter.dart';

/// Terrain layer with a rich, hand-illustrated topographic treatment.
class HdTerrainLayer extends StatelessWidget {
  const HdTerrainLayer({
    super.key,
    required this.features,
    this.paintBase = true,
    this.paintWater = true,
    this.paintAreas = true,
    this.paintLines = true,
  });

  final MapFeatureCollection features;
  final bool paintBase;
  final bool paintWater;
  final bool paintAreas;
  final bool paintLines;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final isDark =
        Theme.of(context).extension<WildBitColorsExt>()?.isDark ?? false;
    return RepaintBoundary(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            size: constraints.biggest,
            painter: HdTerrainPainter(
              camera: camera,
              features: features,
              isDark: isDark,
              paintBase: paintBase,
              paintWater: paintWater,
              paintAreas: paintAreas,
              paintLines: paintLines,
            ),
          ),
        ),
      ),
    );
  }
}
