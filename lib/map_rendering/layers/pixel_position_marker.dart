import 'package:flutter/material.dart';

/// Low-cost, non-navigational position cue rendered below Bit.
class PixelPositionMarker extends StatelessWidget {
  const PixelPositionMarker({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _PositionPainter(), size: Size.infinite);
}

class _PositionPainter extends CustomPainter {
  const _PositionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 12.0;
    final ring = Paint()
      ..color = const Color(0xAAE9C34A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ring);
    final core = Paint()..color = const Color(0xFF2D718A);
    canvas.drawRect(Rect.fromCenter(center: center, width: 7, height: 7), core);
    final outline = Paint()
      ..color = const Color(0xFFF6E6A6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 9, height: 9),
      outline,
    );
  }

  @override
  bool shouldRepaint(_PositionPainter oldDelegate) => false;
}
