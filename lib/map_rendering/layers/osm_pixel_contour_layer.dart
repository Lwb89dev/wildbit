import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../composition/pan_projection_frame.dart';
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
  // Contours of the snapshot in their stable seed order, computed once.
  MapFeatureCollection? _contourSource;
  List<LineFeature> _contoursBySeed = const [];
  // Contours projected into the current pan frame.
  PanProjectionFrame? _frame;
  bool? _frameInteracting;
  final Map<LineFeature, _ProjectedContour?> _frameContours = {};
  Offset _offset = Offset.zero;

  @override
  void didUpdateWidget(covariant OsmPixelContourLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      _projectedViewKey = null;
      _projectedContours = null;
      _frameContours.clear();
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
          painter: _ContourPainter(
            camera: camera,
            offset: _offset,
            contours: contours,
          ),
        ),
      ),
    );
  }

  List<_ProjectedContour> _projectForCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final interacting = MapRenderingBudget.mapInteracting;
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
      interacting,
    );
    final cached = _projectedContours;
    if (cached != null && _projectedViewKey == viewKey) return cached;
    final frame = _frame;
    if (frame == null ||
        !frame.accepts(camera) ||
        _frameInteracting != interacting) {
      _frame = PanProjectionFrame(camera);
      _frameInteracting = interacting;
      _frameContours.clear();
    }
    final offset = _offset = _frame!.offsetFor(camera);
    // The budget still selects from the contours in view, in seed order;
    // only their projections are reused while the camera pans.
    final limit = MapRenderingBudget.contourPaintLimit(camera.zoom);
    final projected = <_ProjectedContour>[];
    var selected = 0;
    for (final contour in _contoursInSeedOrder()) {
      if (selected >= limit) break;
      if (!MapRenderingBudget.lineMayBeVisible(contour, bounds)) continue;
      selected++;
      final projection = _frameContours.containsKey(contour)
          ? _frameContours[contour]
          : _frameContours[contour] = _project(contour, camera, offset);
      if (projection != null) projected.add(projection);
    }
    _projectedViewKey = viewKey;
    _projectedContours = List.unmodifiable(projected);
    return _projectedContours!;
  }

  List<LineFeature> _contoursInSeedOrder() {
    if (identical(_contourSource, widget.features)) return _contoursBySeed;
    _contourSource = widget.features;
    return _contoursBySeed = List.unmodifiable(
      widget.features.lines
          .where((line) => line.kind == MapFeatureKind.contourLine)
          .toList(growable: false)
        ..sort(
          (a, b) => OsmLineProjector.seedFor(
            a,
          ).compareTo(OsmLineProjector.seedFor(b)),
        ),
    );
  }

  static _ProjectedContour? _project(
    LineFeature contour,
    MapCamera camera,
    Offset offset,
  ) {
    final points = OsmLineProjector.projectSimplified(
      contour,
      (point) => PanProjectionFrame.project(camera, offset, point),
      minimumDistancePixels: MapRenderingBudget.contourPointDistancePixels(
        camera.zoom,
      ),
      maximumPoints: MapRenderingBudget.contourMaximumPoints(camera.zoom),
    );
    return points.length >= 2 ? _ProjectedContour(points) : null;
  }
}

class _ContourPainter extends CustomPainter {
  const _ContourPainter({
    required this.camera,
    required this.offset,
    required this.contours,
  });

  final MapCamera camera;

  /// Translation from the contours' pan frame to the screen.
  final Offset offset;
  final List<_ProjectedContour> contours;

  @override
  void paint(Canvas canvas, Size size) {
    final width = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .65,
      max: 1.25,
    );
    final reliefStrength = ((camera.zoom - 9) / 5).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final contour in contours) {
      final path = contour.path;
      if (reliefStrength > 0) {
        // The relief highlight is the same line one pixel higher.
        canvas.translate(0, -1);
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(
              0xFF6F7454,
            ).withValues(alpha: .25 * reliefStrength)
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.bevel
            ..strokeWidth = width,
        );
        canvas.translate(0, 1);
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ContourPainter oldDelegate) =>
      oldDelegate.offset != offset ||
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.contours != contours;
}

class _ProjectedContour {
  _ProjectedContour(this.points);

  /// Simplified contour in pan-frame coordinates.
  final List<Offset> points;

  late final Path path = () {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }();
}
