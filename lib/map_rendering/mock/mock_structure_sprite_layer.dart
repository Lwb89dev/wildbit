import 'package:flutter/material.dart';

/// Real foreground structures. Their feet are anchored in logical map pixels,
/// so replacing the mock scene with geographic placements needs no layout API.
class MockStructureSpriteLayer extends StatelessWidget {
  const MockStructureSpriteLayer({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.hardEdge,
    children: const [
      _AnchoredSprite('assets/map/mock/structures/bridge_foot_horizontal_v2.png', 198, 123, 24, 20, 48, 24),
      _AnchoredSprite('assets/map/mock/structures/hut_bivouac.png', 57, 62, 16, 30, 32, 32),
      _AnchoredSprite('assets/map/mock/structures/guidepost_multi.png', 104, 147, 8, 22, 16, 24),
      _AnchoredSprite('assets/map/mock/structures/trail_marker_low.png', 132, 104, 4, 10, 8, 12),
    ],
  );
}

class _AnchoredSprite extends StatelessWidget {
  const _AnchoredSprite(this.path, this.footX, this.footY, this.anchorX,
      this.anchorY, this.width, this.height);

  final String path;
  final double footX;
  final double footY;
  final double anchorX;
  final double anchorY;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Positioned(
    left: footX - anchorX,
    top: footY - anchorY,
    width: width,
    height: height,
    child: Image.asset(path, filterQuality: FilterQuality.none, isAntiAlias: false),
  );
}
