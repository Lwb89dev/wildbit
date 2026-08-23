import 'package:flutter/material.dart';

/// The prototype's hiking path is itself a pixel tile composition.  It is not
/// a coloured stroke, so it can later be selected from an OSM trail class.
class MockTrailTextureLayer extends StatelessWidget {
  const MockTrailTextureLayer({super.key});

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const _TrailClipper(),
    child: const DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/map/mock/terrain/trail_base_1.png'),
          repeat: ImageRepeat.repeat,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: SizedBox.expand(),
    ),
  );
}

class _TrailClipper extends CustomClipper<Path> {
  const _TrailClipper();

  @override
  Path getClip(Size size) {
    final x = size.width / 256;
    final y = size.height / 256;
    return Path()
      ..moveTo(84 * x, size.height)
      ..cubicTo(88 * x, 220 * y, 116 * x, 202 * y, 105 * x, 169 * y)
      ..cubicTo(94 * x, 136 * y, 143 * x, 115 * y, 123 * x, 83 * y)
      ..cubicTo(107 * x, 51 * y, 118 * x, 22 * y, 100 * x, 0)
      ..lineTo(116 * x, 0)
      ..cubicTo(130 * x, 22 * y, 119 * x, 50 * y, 139 * x, 79 * y)
      ..cubicTo(160 * x, 115 * y, 107 * x, 136 * y, 121 * x, 166 * y)
      ..cubicTo(136 * x, 200 * y, 103 * x, 221 * y, 100 * x, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_TrailClipper oldClipper) => false;
}
