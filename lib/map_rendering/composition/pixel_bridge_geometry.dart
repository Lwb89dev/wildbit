import 'dart:math' as math;
import 'dart:ui';

import '../performance/map_rendering_budget.dart';

class PixelBridgeGeometry {
  const PixelBridgeGeometry({
    required this.center,
    required this.angle,
    required this.width,
    required this.height,
    required this.capWidth,
    required this.midSegments,
  });

  final Offset center;
  final double angle;
  final double width;
  final double height;
  final double capWidth;
  final int midSegments;

  static PixelBridgeGeometry? fromProjected({
    required Offset start,
    required Offset end,
    required double zoom,
  }) {
    final delta = end - start;
    final projectedLength = delta.distance;
    if (!projectedLength.isFinite || projectedLength < .05) return null;

    final scale = MapRenderingBudget.decorativeScale(
      zoom,
      min: .55,
      max: 1.25,
    );
    // Projection already includes zoom: multiplying by another zoom factor
    // would make the bridge shrink twice while dezooming.
    final width = projectedLength.clamp(14.0, 160.0).toDouble();
    final height = (12 * scale).clamp(7.0, 15.0).toDouble();
    final capWidth = math.min(width * .28, 10 * scale).clamp(4.0, 12.0);
    final usableMiddle = math.max(1.0, width - capWidth * 2);
    final midSegments = math.max(1, (usableMiddle / (10 * scale)).ceil());

    return PixelBridgeGeometry(
      center: Offset.lerp(start, end, .5)!,
      angle: math.atan2(delta.dy, delta.dx),
      width: width,
      height: height,
      capWidth: capWidth.toDouble(),
      midSegments: midSegments,
    );
  }
}
