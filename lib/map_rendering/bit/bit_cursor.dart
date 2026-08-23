import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import 'bit_animation_controller.dart';
import 'bit_frame_metrics.dart';
import 'bit_motion_state.dart';
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
        final tilt = isWalking ? math.sin(phase) * .025 : 0.0;
        final metrics = BitFrameMetrics.forFrame(
          controller.state,
          controller.frameIndex,
        );
        final normalizedOffset =
            metrics.verticalCorrection / 150 * widget.pixelSize * 1.5;
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
                  offset: Offset(0, verticalOffset + normalizedOffset),
                  child: Transform.rotate(
                    angle: tilt,
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scale: metrics.scaleCorrection,
                      alignment: Alignment.topCenter,
                      child: Image.asset(
                        _currentFramePath(),
                        width: widget.pixelSize,
                        height: widget.pixelSize * 1.5,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        gaplessPlayback: true,
                      ),
                    ),
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
