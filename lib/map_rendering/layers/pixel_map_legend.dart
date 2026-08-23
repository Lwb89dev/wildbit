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
        BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(1, 2)),
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
        ],
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 10,
        height: 6,
        child: DecoratedBox(decoration: BoxDecoration(color: color)),
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
