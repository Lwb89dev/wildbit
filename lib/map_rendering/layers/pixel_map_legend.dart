import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact map legend using the same palette as the pixel compositor.
class PixelMapLegend extends StatelessWidget {
  const PixelMapLegend({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE6142A25),
      border: Border.all(color: const Color(0xFFB9A66A), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55000000),
          blurRadius: 4,
          offset: Offset(1, 2),
        ),
      ],
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: const [
          _LegendItem(Color(0xFF4B9CC1), 'Acqua'),
          _LegendItem(Color(0xFFD2A563), 'Sentiero'),
          _LegendItem(Color(0xFFB58B55), 'Strada'),
          _LegendItem(Color(0xFF4E873C), 'Vegetazione'),
          _LegendItem(Color(0xFFD69A2D), 'T1–T6'),
          _LegendItem(Color(0xFFD53A35), 'Accesso vietato', dashed: true),
          _LegendItem(Color(0xFFE9D9A2), 'Traccia debole', dotted: true),
          _LegendItem(Color(0xFFE4A43B), 'Condizionale', dotted: true),
        ],
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(
    this.color,
    this.label, {
    this.dashed = false,
    this.dotted = false,
  });

  final Color color;
  final String label;
  final bool dashed;
  final bool dotted;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 6,
        child: CustomPaint(
          painter: _LegendSwatchPainter(color, dashed: dashed, dotted: dotted),
        ),
      ),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFFF4D2),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      ),
    ],
  );
}

class _LegendSwatchPainter extends CustomPainter {
  const _LegendSwatchPainter(
    this.color, {
    required this.dashed,
    required this.dotted,
  });

  final Color color;
  final bool dashed;
  final bool dotted;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dotted ? 2 : size.height
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = false;
    if (!dashed && !dotted) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    final length = dotted ? 2.0 : 4.0;
    final gap = dotted ? 3.0 : 2.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + length, size.width), size.height / 2),
        paint,
      );
      x += length + gap;
    }
  }

  @override
  bool shouldRepaint(_LegendSwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dashed != dashed ||
      oldDelegate.dotted != dotted;
}
