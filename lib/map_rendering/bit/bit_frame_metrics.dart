import 'bit_motion_state.dart';

/// Alpha-bound measurements of the authored 100×150 Bit frames.
/// Rendering normalizes these bounds to one visual height and ground line,
/// while preserving every source pixel and pose.
class BitFrameMetrics {
  const BitFrameMetrics._(
    this.contentWidth,
    this.contentHeight,
    this.contentLeft,
    this.contentTop,
    this.anchorX,
  );

  static const double targetVisualHeight = 135;
  static const double targetVisualWidth = 95;
  static const double targetBaseline = 141;

  final double contentWidth;
  final double contentHeight;

  /// Pixel offset of the alpha bounds inside the authored 100×150 canvas.
  final double contentLeft;
  final double contentTop;

  /// Source-canvas x coordinate of Bit's planted-foot pivot. The artwork's
  /// transparent bounds move with the map/arms, but this point must stay on
  /// the user's map position.
  final double anchorX;

  double get scaleCorrection => targetVisualHeight / contentHeight;
  double get horizontalScaleCorrection => targetVisualWidth / contentWidth;
  double get verticalCorrection =>
      targetBaseline - contentHeight * scaleCorrection;

  static BitFrameMetrics forFrame(BitMotionState state, int frameIndex) {
    final index = switch (state) {
      BitMotionState.standing => 0,
      BitMotionState.walking => frameIndex.clamp(0, _walkHeights.length - 1),
      BitMotionState.checkingMap => frameIndex.clamp(0, _mapHeights.length - 1),
    };
    final width = switch (state) {
      BitMotionState.standing => 100,
      BitMotionState.walking => _walkWidths[index],
      BitMotionState.checkingMap => _mapWidths[index],
    };
    final height = switch (state) {
      BitMotionState.standing => 141,
      BitMotionState.walking => _walkHeights[index],
      BitMotionState.checkingMap => _mapHeights[index],
    };
    final left = switch (state) {
      BitMotionState.standing => 0,
      BitMotionState.walking => _walkLeft[index],
      BitMotionState.checkingMap => _mapLeft[index],
    };
    final top = switch (state) {
      BitMotionState.standing => 0,
      BitMotionState.walking => _walkTop[index],
      BitMotionState.checkingMap => _mapTop[index],
    };
    final anchor = switch (state) {
      BitMotionState.standing => 50,
      BitMotionState.walking => _walkAnchorX[index],
      BitMotionState.checkingMap => _mapAnchorX[index],
    };
    return BitFrameMetrics._(
      width.toDouble(),
      height.toDouble(),
      left.toDouble(),
      top.toDouble(),
      anchor.toDouble(),
    );
  }

  static const _walkLeft = <int>[
    5,
    5,
    5,
    5,
    5,
    5,
    6,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
  ];

  static const _walkTop = <int>[
    17,
    16,
    18,
    18,
    18,
    18,
    15,
    15,
    16,
    16,
    20,
    19,
    22,
    16,
    15,
    15,
  ];

  // The walking exports share the same authored foot placement.
  static const _walkAnchorX = <int>[
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
    50,
  ];

  static const _walkWidths = <int>[
    90,
    90,
    90,
    90,
    90,
    90,
    88,
    89,
    90,
    90,
    90,
    90,
    90,
    90,
    89,
    89,
  ];

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

  static const _mapWidths = <int>[
    84,
    84,
    95,
    95,
    95,
    95,
    95,
    95,
    95,
    95,
    93,
    91,
  ];

  static const _mapLeft = <int>[8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 3, 4];

  static const _mapTop = <int>[10, 10, 22, 30, 26, 26, 27, 28, 26, 22, 10, 10];

  // Midpoint between Bit's two planted boots, measured on the authored
  // 100×150 canvas for each map-reading frame.
  static const _mapAnchorX = <int>[
    56,
    58,
    45,
    43,
    44,
    43,
    44,
    43,
    44,
    45,
    52,
    52,
  ];
}
