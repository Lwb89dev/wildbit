import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Static preview of the live recorded-track overlay used by the real map.
class MockRecordedTrackLayer extends StatelessWidget {
  const MockRecordedTrackLayer({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size.infinite,
    painter: _MockRecordedTrackPainter(),
  );
}

class _MockRecordedTrackPainter extends CustomPainter {
  const _MockRecordedTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(92, 256)
      ..cubicTo(95, 219, 126, 202, 113, 167)
      ..cubicTo(100, 135, 151, 115, 131, 81)
      ..cubicTo(113, 49, 124, 22, 108, 0);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xB52E3625)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE5B34D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
    // Keep a marker at the route origin. The current endpoint is Bit's own
    // ground anchor; drawing a square there leaks out from under his feet and
    // reads as a beige rectangle attached to the sprite.
    for (final point in const [Offset(92, 256)]) {
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 8, height: 8),
        Paint()..color = const Color(0xFFE5B34D),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MockRecordedTrackPainter oldDelegate) => false;
}
