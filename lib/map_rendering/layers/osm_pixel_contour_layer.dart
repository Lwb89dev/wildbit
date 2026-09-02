import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../performance/map_rendering_budget.dart';

/// Draws contour geometry only when supplied by an elevation-aware source.
/// OSM paths are never reinterpreted as elevation data.
class OsmPixelContourLayer extends StatefulWidget {
  const OsmPixelContourLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelContourLayer> createState() => _OsmPixelContourLayerState();
}

class _OsmPixelContourLayerState extends State<OsmPixelContourLayer> {
  int? _projectedViewKey;
  List<_ProjectedContour>? _projectedContours;

  @override
  void didUpdateWidget(covariant OsmPixelContourLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      _projectedViewKey = null;
      _projectedContours = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final contours = _projectForCamera(camera);
    if (contours.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ContourPainter(camera: camera, contours: contours),
        ),
      ),
    );
  }

  List<_ProjectedContour> _projectForCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      identityHashCode(widget.features),
      camera.center.latitude,
      camera.center.longitude,
      camera.zoom,
      camera.rotation,
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      MapRenderingBudget.mapInteracting,
    );
    final cached = _projectedContours;
    if (cached != null && _projectedViewKey == viewKey) return cached;
    final contours =
        widget.features.lines
            .where((line) => line.kind == MapFeatureKind.contourLine)
            .where((line) => MapRenderingBudget.lineMayBeVisible(line, bounds))
            .toList(growable: false)
          ..sort(
            (a, b) => OsmLineProjector.seedFor(
              a,
            ).compareTo(OsmLineProjector.seedFor(b)),
          );
    final limit = MapRenderingBudget.contourPaintLimit(camera.zoom);
    final budgeted = contours.length <= limit
        ? contours
        : contours.take(limit).toList(growable: false);
    final projected = <_ProjectedContour>[
      for (final contour in budgeted)
        if (OsmLineProjector.projectSimplified(
              contour,
              camera.latLngToScreenOffset,
              minimumDistancePixels:
                  MapRenderingBudget.contourPointDistancePixels(camera.zoom),
              maximumPoints: MapRenderingBudget.contourMaximumPoints(
                camera.zoom,
              ),
            )
            case final points when points.length >= 2)
          _ProjectedContour(points),
    ];
    _projectedViewKey = viewKey;
    _projectedContours = List.unmodifiable(projected);
    return _projectedContours!;
  }
}

class _ContourPainter extends CustomPainter {
  const _ContourPainter({required this.camera, required this.contours});

  final MapCamera camera;
  final List<_ProjectedContour> contours;

  @override
  void paint(Canvas canvas, Size size) {
    final width = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .65,
      max: 1.25,
    );
    for (final contour in contours) {
      final points = contour.points;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final reliefStrength = ((camera.zoom - 9) / 5).clamp(0.0, 1.0);
      if (reliefStrength > 0) {
        canvas.drawPath(
          path.shift(const Offset(0, -1)),
          Paint()
            ..color = const Color(
              0xFF6F7454,
            ).withValues(alpha: .25 * reliefStrength)
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

class _ProjectedContour {
  const _ProjectedContour(this.points);

  final List<Offset> points;
}
