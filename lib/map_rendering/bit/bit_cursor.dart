import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../performance/map_rendering_budget.dart';
import 'bit_animation_controller.dart';
import 'bit_motion_state.dart';
import 'bit_normalized_sprite.dart';
import 'bit_sprite_atlas.dart';

/// Bit himself: the animated sprite shown at the user's GPS position.
/// Advances [BitAnimationController] from the shared, battery-bounded actor
/// clock so callers only need to feed it movement samples via [controller].
class BitCursor extends StatefulWidget {
  const BitCursor({super.key, required this.controller, this.pixelSize = 72});

  final BitAnimationController controller;
  final double pixelSize;

  @override
  State<BitCursor> createState() => _BitCursorState();
}

class _BitCursorState extends State<BitCursor> {
  static const _tickInterval = Duration(milliseconds: 50);
  bool _precacheStarted = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncClockBudget);
    _syncClockBudget();
    MapRenderingBudget.actorClock.addListener(_onTick);
  }

  void _syncClockBudget() => MapRenderingBudget.setActorWalking(
    widget.controller.state == BitMotionState.walking,
  );

  void _onTick() {
    // The global clock is deliberately stepped down to 2 fps while Bit is
    // standing or reading the map. Feed the controller that real cadence,
    // otherwise its 2 fps animation would accidentally become 0.2 fps.
    final interval = widget.controller.state == BitMotionState.walking
        ? _tickInterval
        : const Duration(milliseconds: 500);
    widget.controller.tick(interval);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncClockBudget);
    MapRenderingBudget.setActorWalking(false);
    MapRenderingBudget.actorClock.removeListener(_onTick);
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
