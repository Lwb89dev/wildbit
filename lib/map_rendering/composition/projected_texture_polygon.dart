import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A repeated pixel texture whose origin follows the projected polygon.
/// This prevents the terrain artwork from swimming underneath the map while
/// the camera pans.
class ProjectedTexturePolygon extends StatelessWidget {
  const ProjectedTexturePolygon({
    super.key,
    required this.polygon,
    required this.asset,
    this.borderColor,
    this.borderWidth = 0,
  });

  final List<Offset> polygon;
  final String asset;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    if (polygon.length < 3) return const SizedBox.shrink();
    var left = polygon.first.dx;
    var right = left;
    var top = polygon.first.dy;
    var bottom = top;
    for (final point in polygon.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    const padding = 2.0;
    final bounds = Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
    if (bounds.width <= 0 || bounds.height <= 0) {
      return const SizedBox.shrink();
    }
    final local = [
      for (final point in polygon) point - bounds.topLeft,
    ];
    return Positioned.fromRect(
      rect: bounds,
      child: ClipPath(
        clipper: _LocalPolygonClipper(local),
        child: DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(asset),
              repeat: ImageRepeat.repeat,
              filterQuality: FilterQuality.none,
            ),
          ),
          child: borderColor == null || borderWidth <= 0
              ? const SizedBox.expand()
              : CustomPaint(
                  painter: _PolygonBorderPainter(
                    local,
                    borderColor!,
                    borderWidth,
                  ),
                ),
        ),
      ),
    );
  }
}

class _LocalPolygonClipper extends CustomClipper<Path> {
  const _LocalPolygonClipper(this.polygon);

  final List<Offset> polygon;

  @override
  Path getClip(Size size) => Path()..addPolygon(polygon, true);

  @override
  bool shouldReclip(_LocalPolygonClipper oldClipper) =>
      oldClipper.polygon != polygon;
}

class _PolygonBorderPainter extends CustomPainter {
  const _PolygonBorderPainter(this.polygon, this.color, this.width);

  final List<Offset> polygon;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()..addPolygon(polygon, true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.bevel
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_PolygonBorderPainter oldDelegate) =>
      oldDelegate.polygon != polygon ||
      oldDelegate.color != color ||
      oldDelegate.width != width;
}
