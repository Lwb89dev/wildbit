import 'dart:async';

import 'package:flutter/material.dart';

import '../bit/bit_motion_state.dart';
import '../bit/bit_normalized_sprite.dart';
import '../bit/bit_sprite_atlas.dart';

/// Lightweight Bit actor used by the desktop mock. It uses the authored map
/// sprites rather than the placeholder painter, so the preview exercises the
/// same silhouette and pixel filtering as the real map layer.
class MockBitSpriteLayer extends StatefulWidget {
  const MockBitSpriteLayer({super.key});

  @override
  State<MockBitSpriteLayer> createState() => _MockBitSpriteLayerState();
}

class _MockBitSpriteLayerState extends State<MockBitSpriteLayer> {
  static const _foot = Offset(119, 167);
  // The authored map frames are 100×150. A 24×36 logical box keeps Bit
  // subordinate to the tall tree silhouettes in the 256 px mock chunk.
  static const _pixelSize = 24.0;
  static const _frameStep = Duration(milliseconds: 180);

  Timer? _timer;
  int _frame = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_frameStep, (_) {
      if (mounted) {
        setState(() => _frame = _frame % BitSpriteAtlas.mapFrameCount + 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: _foot.dx - _pixelSize / 2,
    top: _foot.dy - _pixelSize * 1.5,
    width: _pixelSize,
    height: _pixelSize * 1.5,
    child: BitNormalizedSprite(
      assetPath: BitSpriteAtlas.mapFrame(_frame),
      state: BitMotionState.checkingMap,
      frameIndex: _frame - 1,
      width: _pixelSize,
      height: _pixelSize * 1.5,
    ),
  );
}
