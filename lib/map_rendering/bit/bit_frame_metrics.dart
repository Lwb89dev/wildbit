import 'bit_motion_state.dart';

/// Alpha-bound measurements of the authored 100×150 Bit frames.
/// Rendering normalizes these bounds to one visual height and ground line,
/// while preserving every source pixel and pose.
class BitFrameMetrics {
  const BitFrameMetrics._(this.contentHeight);

  static const double targetVisualHeight = 135;
  static const double targetBaseline = 141;

  final double contentHeight;

  double get scaleCorrection => targetVisualHeight / contentHeight;
  double get verticalCorrection =>
      targetBaseline - contentHeight * scaleCorrection;

  static BitFrameMetrics forFrame(BitMotionState state, int frameIndex) {
    final height = switch (state) {
      BitMotionState.standing => 141,
      BitMotionState.walking => _walkHeights[
        frameIndex.clamp(0, _walkHeights.length - 1)
      ],
      BitMotionState.checkingMap => _mapHeights[
        frameIndex.clamp(0, _mapHeights.length - 1)
      ],
    };
    return BitFrameMetrics._(height.toDouble());
  }

  static const _walkHeights = <int>[
    133,
    134,
    132,
    132,
    132,
    132,
    135,
    135,
    134,
    134,
    130,
    131,
    128,
    134,
    135,
    135,
  ];

  static const _mapHeights = <int>[
    140,
    140,
    128,
    120,
    124,
    124,
    123,
    122,
    124,
    128,
    140,
    140,
  ];
}
