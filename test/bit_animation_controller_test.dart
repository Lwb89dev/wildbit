import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/domain/enums/direction8.dart';
import 'package:wildbit/map_rendering/bit/bit_animation_controller.dart';
import 'package:wildbit/map_rendering/bit/bit_frame_metrics.dart';
import 'package:wildbit/map_rendering/bit/bit_motion_state.dart';

void main() {
  test('Bit reads the map at rest and resumes a fluid walking cycle', () {
    final controller = BitAnimationController(idleTimeout: Duration.zero);

    controller.tick(Duration.zero);
    expect(controller.state, BitMotionState.checkingMap);
    expect(controller.frameIndex, 0);

    controller.tick(const Duration(seconds: 1));
    expect(controller.frameIndex, 2);

    controller.reportMovement(isMoving: true, headingDegrees: 90);
    expect(controller.state, BitMotionState.walking);
    expect(controller.direction, Direction8.e);

    controller.tick(const Duration(milliseconds: 100));
    expect(controller.frameIndex, 1);
    expect(controller.motionPhase, isNot(0));

    controller.reportMovement(isMoving: false);
    expect(controller.state, BitMotionState.standing);
  });

  test('all Bit animations share one normalized visual height', () {
    for (final state in BitMotionState.values) {
      final count = switch (state) {
        BitMotionState.standing => 1,
        BitMotionState.walking => 16,
        BitMotionState.checkingMap => 12,
      };
      for (var frame = 0; frame < count; frame++) {
        final metrics = BitFrameMetrics.forFrame(state, frame);
        expect(
          metrics.contentHeight * metrics.scaleCorrection,
          closeTo(BitFrameMetrics.targetVisualHeight, .001),
        );
        expect(metrics.verticalCorrection, closeTo(6, .001));
      }
    }
  });
}
