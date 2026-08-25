import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/geo_fix.dart';
import '../composition/osm_line_projector.dart';

/// Pixel-art overlay for the user's recorded track.
///
/// The source fixes remain untouched. Only the projected paint geometry is
/// simplified, so camera zoom and bearing can change without losing the
/// recorded route or moving it into geographic coordinates of its own.
class PixelRecordedTrackLayer extends StatelessWidget {
  const PixelRecordedTrackLayer({
    super.key,
    required this.points,
    this.color = const Color(0xFFE5B34D),
  });

  final List<GeoFix> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RecordedTrackPainter(
            camera: camera,
            points: points,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RecordedTrackPainter extends CustomPainter {
  const _RecordedTrackPainter({
    required this.camera,
    required this.points,
    required this.color,
  });

  final MapCamera camera;
  final List<GeoFix> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final projected = OsmLineProjector.projectSimplifiedPoints(
      [for (final point in points) point.position],
      camera.latLngToScreenOffset,
      minimumDistancePixels: ((18 - camera.zoom) * .45).clamp(1.2, 5.0),
      maximumPoints: camera.zoom >= 14 ? 2048 : 768,
    );
    if (!OsmLineProjector.overlapsViewport(projected, size, margin: 32)) {
      return;
    }

    final scale = ((camera.zoom - 11) / 5).clamp(0.0, 1.0);
    final width = 2.0 + scale * 2.0;
    _stroke(
      canvas,
      projected,
      width: width + 2.4,
      color: const Color(0xB52E3625),
    );
    _stroke(canvas, projected, width: width, color: color);

    final start = camera.latLngToScreenOffset(points.first.position);
    final current = camera.latLngToScreenOffset(points.last.position);
    _marker(canvas, start, radius: 3.5 + scale, fill: const Color(0xFFF8E1A5));
    // The current endpoint is occupied by Bit. A second square marker here
    // leaks from under the sprite during map-reading frames, so only the
    // route origin receives a standalone marker.
    final heading = points.last.headingDegrees;
    if (heading != null && heading.isFinite) {
      final radians = heading * math.pi / 180;
      final direction = Offset(math.sin(radians), -math.cos(radians));
      final tip = current + direction * (9 + scale * 3);
      canvas.drawLine(
        current,
        tip,
        Paint()
          ..color = const Color(0xFF2E3625)
          ..strokeWidth = math.max(1.5, width * .7)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
      );
    }
  }

  void _stroke(
    Canvas canvas,
    List<Offset> points, {
    required double width,
    required Color color,
  }) {
    if (points.length < 2) return;
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.bevel
        ..isAntiAlias = false,
    );
  }

  void _marker(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color fill,
  }) {
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(1.5, 1.5),
        width: radius * 2,
        height: radius * 2,
      ),
      Paint()..color = const Color(0x77202C21),
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RecordedTrackPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.points != points ||
      oldDelegate.color != color;
}
