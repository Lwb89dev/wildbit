import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import 'bit_animation_controller.dart';
import 'bit_motion_state.dart';
import 'bit_normalized_sprite.dart';
import 'bit_sprite_atlas.dart';

/// Bit himself: the animated sprite shown at the user's GPS position.
/// Owns the ticker that drives [BitAnimationController] frame-by-frame so
/// callers only need to feed it movement samples via [controller].
class BitCursor extends StatefulWidget {
  const BitCursor({super.key, required this.controller, this.pixelSize = 72});

  final BitAnimationController controller;
  final double pixelSize;

  @override
  State<BitCursor> createState() => _BitCursorState();
}

class _BitCursorState extends State<BitCursor>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _precacheStarted = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    widget.controller.tick(delta);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precacheStarted) return;
    _precacheStarted = true;
    // Decode the first stable pose before the animation can switch to its
    // first map frame. The normalized sprite still keeps a previous-frame
    // fallback for later asynchronous frame loads.
    precacheImage(AssetImage(BitSpriteAtlas.standing), context);
    precacheImage(AssetImage(BitSpriteAtlas.mapFrame(1)), context);
  }

  String _currentFramePath() {
    final c = widget.controller;
    return switch (c.state) {
      BitMotionState.standing => BitSpriteAtlas.standing,
      BitMotionState.checkingMap => BitSpriteAtlas.mapFrame(c.frameIndex + 1),
      BitMotionState.walking => BitSpriteAtlas.walkFrame(
        c.direction,
        c.frameIndex + 1,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final isWalking = controller.state == BitMotionState.walking;
        final phase = controller.motionPhase;
        final stride = isWalking ? math.sin(phase) : 0.0;
        final verticalOffset = isWalking ? stride * 1.25 : 0.0;
        return RepaintBoundary(
          child: SizedBox(
            width: widget.pixelSize,
            height: widget.pixelSize * 1.5,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: widget.pixelSize * 0.04,
                  child: Container(
                    width: widget.pixelSize * 0.42,
                    height: widget.pixelSize * 0.14,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, verticalOffset),
                  child: BitNormalizedSprite(
                    assetPath: _currentFramePath(),
                    state: controller.state,
                    frameIndex: controller.frameIndex,
                    width: widget.pixelSize,
                    height: widget.pixelSize * 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
