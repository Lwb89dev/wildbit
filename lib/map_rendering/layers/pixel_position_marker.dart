import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated, non-navigational position cue rendered below Bit.
class PixelPositionMarker extends StatefulWidget {
  const PixelPositionMarker({super.key});

  @override
  State<PixelPositionMarker> createState() => _PixelPositionMarkerState();
}

class _PixelPositionMarkerState extends State<PixelPositionMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => CustomPaint(
      painter: _PositionPainter(_pulse.value),
      size: Size.infinite,
    ),
  );
}

class _PositionPainter extends CustomPainter {
  const _PositionPainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 12 + math.sin(phase * math.pi * 2) * 2;
    final ring = Paint()
      ..color = const Color(0xAAE9C34A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ring);
    final core = Paint()..color = const Color(0xFF2D718A);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 7, height: 7),
      core,
    );
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
  bool shouldRepaint(_PositionPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
