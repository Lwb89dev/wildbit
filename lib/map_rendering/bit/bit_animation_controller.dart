import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../../domain/enums/direction8.dart';
import 'bit_motion_state.dart';
import 'bit_sprite_atlas.dart';

/// Drives Bit's frame-by-frame state: which sprite to show, given whether
/// the user is walking (and in what direction) or standing still long
/// enough to trigger the "check the map" idle animation.
class BitAnimationController extends ChangeNotifier {
  BitAnimationController({
    this.idleTimeout = const Duration(milliseconds: 1200),
    this.walkFps = 10,
    this.mapFps = 2,
  });

  final Duration idleTimeout;
  final int walkFps;
  final int mapFps;

  Direction8 direction = Direction8.s;
  BitMotionState state = BitMotionState.standing;
  int frameIndex = 0;
  double motionPhase = 0;

  double _frameAccumulator = 0;
  DateTime _stoppedAt = DateTime.now();
  bool _isMoving = false;
  int _mapBeat = 0;

  // Bit reaches into the pack, unfolds the map, studies it, then keeps the
  // map open while scratching his head in puzzlement before folding it again.
  // Repeated beats intentionally make the reflective part slow and readable.
  static const _mapReadSequence = <int>[
    0,
    1,
    2,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    6,
    7,
    7,
    7,
    8,
    8,
    8,
    9,
    9,
    9,
    10,
    10,
    11,
    11,
    10,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
    1,
  ];

  /// Feed the latest movement sample. [isMoving] should reflect real
  /// displacement (e.g. speed above a small noise threshold), not just
  /// "a GPS fix arrived".
  void reportMovement({required bool isMoving, double? headingDegrees}) {
    if (isMoving) {
      _startWalking(headingDegrees);
    } else {
      _startStandingIfNeeded();
    }
  }

  void _startWalking(double? headingDegrees) {
    var changed = false;
    if (headingDegrees != null) {
      final nextDirection = Direction8.fromBearingDegrees(headingDegrees);
      changed = nextDirection != direction;
      direction = nextDirection;
    }
    _isMoving = true;
    if (state != BitMotionState.walking) {
      state = BitMotionState.walking;
      frameIndex = 0;
      motionPhase = 0;
      _frameAccumulator = 0;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _startStandingIfNeeded() {
    if (!_isMoving) return;
    _isMoving = false;
    state = BitMotionState.standing;
    frameIndex = 0;
    _frameAccumulator = 0;
    _stoppedAt = DateTime.now();
    notifyListeners();
  }

  /// Advance animation time. Call once per frame from a [Ticker].
  void tick(Duration elapsed) {
    var changed = false;
    switch (state) {
      case BitMotionState.walking:
        motionPhase =
            (motionPhase + elapsed.inMicroseconds / 1e6 * math.pi * 3.4) %
            (math.pi * 2);
        _stepFrames(
          elapsed,
          fps: walkFps,
          frameCount: BitSpriteAtlas.walkFrameCount,
          loop: true,
        );
        // Smooth body/staff motion is intentionally updated at display rate;
        // the surrounding map is isolated by repaint boundaries.
        changed = true;
      case BitMotionState.checkingMap:
        changed = _stepMapFrames(elapsed);
      case BitMotionState.standing:
        changed = _maybeStartCheckingMap();
    }
    if (changed) notifyListeners();
  }

  bool _maybeStartCheckingMap() {
    if (DateTime.now().difference(_stoppedAt) < idleTimeout) return false;
    state = BitMotionState.checkingMap;
    _mapBeat = 0;
    frameIndex = _mapReadSequence.first;
    _frameAccumulator = 0;
    return true;
  }

  bool _stepFrames(
    Duration elapsed, {
    required int fps,
    required int frameCount,
    required bool loop,
  }) {
    var changed = false;
    final frameDuration = 1 / fps;
    _frameAccumulator += elapsed.inMicroseconds / 1e6;
    while (_frameAccumulator >= frameDuration) {
      _frameAccumulator -= frameDuration;
      frameIndex++;
      changed = true;
      if (frameIndex < frameCount) continue;
      if (loop) {
        frameIndex = 0;
        continue;
      }
      frameIndex = frameCount - 1;
      return changed;
    }
    return changed;
  }

  bool _stepMapFrames(Duration elapsed) {
    final frameDuration = 1 / mapFps;
    _frameAccumulator += elapsed.inMicroseconds / 1e6;
    var changed = false;
    while (_frameAccumulator >= frameDuration) {
      _frameAccumulator -= frameDuration;
      _mapBeat = (_mapBeat + 1) % _mapReadSequence.length;
      frameIndex = _mapReadSequence[_mapBeat];
      changed = true;
    }
    return changed;
  }
}
