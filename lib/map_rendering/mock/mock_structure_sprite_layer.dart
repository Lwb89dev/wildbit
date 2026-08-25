import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../composition/pixel_bridge_placement.dart';
import 'mock_valley_water_geometry.dart';

/// Real foreground structures. Their feet are anchored in logical map pixels,
/// so replacing the mock scene with geographic placements needs no layout API.
class MockStructureSpriteLayer extends StatelessWidget {
  const MockStructureSpriteLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = PixelBridgePlacement.fromWaterPolygon(
      polygon: MockValleyWaterGeometry.riverPolygon,
      center: const Offset(205, 123),
      direction: const Offset(1, 0),
      shoreMargin: 5,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (bridge != null) _BridgeSprite(placement: bridge),
        // Full-size alpine hut: its footprint reads as a real shelter rather
        // than a small marker and keeps the ground anchor at the doorway.
        // The alpine asset has ten transparent rows below its visible base.
        // Anchor the visible pixels, not the bottom of the source canvas.
        const _AnchoredSprite(
          'assets/map/mock/structures/hut_alpine.png',
          57,
          62,
          30,
          47.5,
          60,
          60,
          47.5,
        ),
        const _AnchoredSprite(
          'assets/map/mock/structures/hut_bivouac.png',
          93,
          86,
          14,
          27,
          28,
          28,
        ),
        const _AnchoredSprite(
          'assets/map/mock/structures/guidepost_multi.png',
          104,
          147,
          8,
          22,
          16,
          24,
        ),
        const _AnchoredSprite(
          'assets/map/mock/structures/trail_marker_low.png',
          132,
          104,
          4,
          10,
          8,
          12,
        ),
      ],
    );
  }
}

class _BridgeSprite extends StatelessWidget {
  const _BridgeSprite({required this.placement});

  final PixelBridgePlacement placement;

  @override
  Widget build(BuildContext context) {
    final width = placement.length;
    const height = 24.0;
    final angle = math.atan2(
      placement.end.dy - placement.start.dy,
      placement.end.dx - placement.start.dx,
    );
    final padding = height;
    return Positioned(
      left: placement.start.dx - padding,
      top: placement.start.dy - height / 2 - padding,
      width: width + padding * 2,
      height: height + padding * 2,
      child: Center(
        child: Transform.rotate(
          angle: angle,
          child: SizedBox(
            width: width,
            height: height,
            child: Image.asset(
              'assets/map/mock/structures/bridge_foot_horizontal_v2.png',
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
              isAntiAlias: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchoredSprite extends StatelessWidget {
  const _AnchoredSprite(
    this.path,
    this.footX,
    this.footY,
    this.anchorX,
    this.anchorY,
    this.width,
    this.height, [
    this.clipHeight,
  ]);

  final String path;
  final double footX;
  final double footY;
  final double anchorX;
  final double anchorY;
  final double width;
  final double height;
  final double? clipHeight;

  @override
  Widget build(BuildContext context) {
    final visibleHeight = clipHeight ?? height;
    final top = clipHeight == null ? footY - anchorY : footY - visibleHeight;
    return Positioned(
      left: footX - anchorX,
      top: top,
      width: width,
      height: visibleHeight,
      child: ClipRect(
        child: SizedBox(
          width: width,
          height: height,
          child: Image.asset(
            path,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
            isAntiAlias: false,
          ),
        ),
      ),
    );
  }
}
