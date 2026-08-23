import 'package:flutter/material.dart';

/// Low terrain props belong below trees in the draw stack.  A boulder may
/// touch a trunk, but it must never visually float in front of the canopy.
class MockLowRockSpriteLayer extends StatelessWidget {
  const MockLowRockSpriteLayer({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    children: [
      _LowRock(39, 87),
      _LowRock(151, 45),
      _LowRock(154, 210),
    ],
  );
}

class _LowRock extends StatelessWidget {
  const _LowRock(this.footX, this.footY);

  final double footX;
  final double footY;

  @override
  Widget build(BuildContext context) => Positioned(
    left: footX - 8,
    top: footY - 14,
    width: 16,
    height: 16,
    child: Image.asset(
      'assets/map/mock/structures/boulder.png',
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
    ),
  );
}
