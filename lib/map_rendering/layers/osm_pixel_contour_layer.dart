import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../performance/map_rendering_budget.dart';

/// Draws contour geometry only when supplied by an elevation-aware source.
/// OSM paths are never reinterpreted as elevation data.
class OsmPixelContourLayer extends StatelessWidget {
  const OsmPixelContourLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final contours = features.lines
        .where((line) => line.kind == MapFeatureKind.contourLine)
        .where(
          (line) => MapRenderingBudget.lineMayBeVisible(
            line,
            camera.visibleBounds,
          ),
        )
        .toList(growable: false)
      ..sort(
        (a, b) => OsmLineProjector.seedFor(a).compareTo(
          OsmLineProjector.seedFor(b),
        ),
      );
    if (contours.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ContourPainter(
            camera: camera,
            contours: contours,
          ),
        ),
      ),
    );
  }
}

class _ContourPainter extends CustomPainter {
  const _ContourPainter({required this.camera, required this.contours});

  final MapCamera camera;
  final List<LineFeature> contours;

  @override
  void paint(Canvas canvas, Size size) {
    final width = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .65,
      max: 1.25,
    );
    for (final contour in contours) {
      final points = OsmLineProjector.projectSimplified(
        contour,
        camera.latLngToScreenOffset,
        minimumDistancePixels: 4,
      );
      if (points.length < 2) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final reliefStrength = ((camera.zoom - 9) / 5).clamp(0.0, 1.0);
      if (reliefStrength > 0) {
        canvas.drawPath(
          path.shift(const Offset(0, -1)),
          Paint()
            ..color = const Color(0xFF6F7454).withValues(
              alpha: .25 * reliefStrength,
            )
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.bevel
            ..strokeWidth = width,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x865B4934)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.bevel
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(_ContourPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.contours != contours;
}
