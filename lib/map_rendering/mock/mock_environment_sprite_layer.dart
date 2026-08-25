import 'package:flutter/material.dart';

import 'mock_valley_water_geometry.dart';

/// Places the first real pixel-art vegetation assets in the fixed mock valley.
/// Placement uses the same ground anchors declared by the asset catalogue.
class MockEnvironmentSpriteLayer extends StatelessWidget {
  const MockEnvironmentSpriteLayer({super.key});

  static const _sprites = <_PlacedSprite>[
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_s.png',
      15,
      24,
      12,
      30,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      44,
      19,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_l.png',
      76,
      34,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      21,
      110,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_s.png',
      47,
      201,
      12,
      30,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      91,
      224,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_coastal.png',
      137,
      21,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      154,
      82,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_coastal.png',
      225,
      32,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_l.png',
      21,
      58,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_s.png',
      55,
      127,
      12,
      30,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_deciduous_l.png',
      77,
      187,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      145,
      151,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_conifer.png',
      159,
      225,
      16,
      46,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/tree_coastal.png',
      229,
      89,
      16,
      38,
      32,
      48,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/shrub_round.png',
      74,
      130,
      8,
      14,
      16,
      16,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/shrub_wide.png',
      137,
      112,
      12,
      14,
      24,
      16,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/shrub_riverside.png',
      150,
      178,
      8,
      14,
      16,
      16,
    ),
    _PlacedSprite(
      'assets/map/mock/objects/shrub_round.png',
      57,
      235,
      8,
      14,
      16,
      16,
    ),
  ];

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.hardEdge,
    children: [
      for (final sprite in _sprites)
        if (!_insideWater(Offset(sprite.footX, sprite.footY)))
          Positioned(
            left: sprite.footX - sprite.anchorX,
            top: sprite.footY - sprite.anchorY,
            width: sprite.width,
            height: sprite.height,
            child: Image.asset(
              sprite.assetPath,
              filterQuality: FilterQuality.none,
              isAntiAlias: false,
            ),
          ),
    ],
  );

  static bool _insideWater(Offset point) {
    return MockValleyWaterGeometry.containsWater(point);
  }
}

class _PlacedSprite {
  const _PlacedSprite(
    this.assetPath,
    this.footX,
    this.footY,
    this.anchorX,
    this.anchorY,
    this.width,
    this.height,
  );

  final String assetPath;
  final double footX;
  final double footY;
  final double anchorX;
  final double anchorY;
  final double width;
  final double height;
}
