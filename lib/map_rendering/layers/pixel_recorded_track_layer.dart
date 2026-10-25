import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/geo_fix.dart';
import '../composition/osm_line_projector.dart';
import '../composition/pan_projection_frame.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel-art overlay for the user's recorded track.
///
/// The source fixes remain untouched. Only the projected paint geometry is
/// simplified, so camera zoom and bearing can change without losing the
/// recorded route or moving it into geographic coordinates of its own.
class PixelRecordedTrackLayer extends StatefulWidget {
  const PixelRecordedTrackLayer({
    super.key,
    required this.points,
    this.color = const Color(0xFFE5B34D),
  });

  final List<GeoFix> points;
  final Color color;

  @override
  State<PixelRecordedTrackLayer> createState() =>
      _PixelRecordedTrackLayerState();
}

class _PixelRecordedTrackLayerState extends State<PixelRecordedTrackLayer> {
  static final _emptyTrack = _ProjectedRecordedTrack.empty();

  // The projected track lives in a pan frame: dragging the map translates
  // it instead of reprojecting every recorded fix on each frame.
  PanProjectionFrame? _frame;
  int? _trackKey;
  Offset _offset = Offset.zero;
  _ProjectedRecordedTrack? _projectionCache;

  @override
  void didUpdateWidget(covariant PixelRecordedTrackLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recording points are intentionally held in a mutable list by the live
    // recorder. The per-build signature below detects appended fixes; this
    // branch handles replacement by a saved/imported immutable track.
    if (!identical(oldWidget.points, widget.points)) {
      _trackKey = null;
      _projectionCache = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final track = _projectForCamera(camera);
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RecordedTrackPainter(
            camera: camera,
            offset: _offset,
            track: track,
            color: widget.color,
          ),
        ),
      ),
    );
  }

  _ProjectedRecordedTrack _projectForCamera(MapCamera camera) {
    final points = widget.points;
    if (points.length < 2) return _emptyTrack;
    final first = points.first;
    final last = points.last;
    final trackKey = Object.hash(
      identityHashCode(points),
      points.length,
      first.timestamp.microsecondsSinceEpoch,
      last.timestamp.microsecondsSinceEpoch,
      last.position.latitude,
      last.position.longitude,
      MapRenderingBudget.mapInteracting,
    );
    final frame = _frame;
    if (_projectionCache == null ||
        frame == null ||
        !frame.accepts(camera) ||
        _trackKey != trackKey) {
      _frame = PanProjectionFrame(camera);
      _trackKey = trackKey;
      final projected = OsmLineProjector.projectSimplifiedPoints(
        [for (final point in points) point.position],
        camera.latLngToScreenOffset,
        minimumDistancePixels:
            MapRenderingBudget.recordedTrackPointDistancePixels(camera.zoom),
        maximumPoints: MapRenderingBudget.recordedTrackMaximumPoints(
          camera.zoom,
        ),
      );
      _projectionCache = _ProjectedRecordedTrack(
        points: List.unmodifiable(projected),
        start: camera.latLngToScreenOffset(first.position),
        current: camera.latLngToScreenOffset(last.position),
        headingDegrees: last.headingDegrees,
      );
    }
    _offset = _frame!.offsetFor(camera);
    return _projectionCache!;
  }
}

class _RecordedTrackPainter extends CustomPainter {
  const _RecordedTrackPainter({
    required this.camera,
    required this.offset,
    required this.track,
    required this.color,
  });

  final MapCamera camera;

  /// Translation from the track's pan frame to the screen.
  final Offset offset;
  final _ProjectedRecordedTrack track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = track.points;
    if (projected.length < 2) return;
    final viewport = PanProjectionFrame.viewportIn(size, offset).inflate(32);
    final bounds = track.bounds;
    if (bounds.right < viewport.left ||
        bounds.left > viewport.right ||
        bounds.bottom < viewport.top ||
        bounds.top > viewport.bottom) {
      return;
    }
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    final scale = ((camera.zoom - 11) / 5).clamp(0.0, 1.0);
    final width = 2.0 + scale * 2.0;
    _stroke(
      canvas,
      track.path,
      width: width + 2.4,
      color: const Color(0xB52E3625),
    );
    _stroke(canvas, track.path, width: width, color: color);

    _marker(
      canvas,
      track.start,
      radius: 3.5 + scale,
      fill: const Color(0xFFF8E1A5),
    );
    // The current endpoint is occupied by Bit. A second square marker here
    // leaks from under the sprite during map-reading frames, so only the
    // route origin receives a standalone marker.
    final heading = track.headingDegrees;
    if (heading != null && heading.isFinite) {
      final radians = heading * math.pi / 180;
      final direction = Offset(math.sin(radians), -math.cos(radians));
      final tip = track.current + direction * (9 + scale * 3);
      canvas.drawLine(
        track.current,
        tip,
        Paint()
          ..color = const Color(0xFF2E3625)
          ..strokeWidth = math.max(1.5, width * .7)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
      );
    }
    canvas.restore();
  }

  void _stroke(
    Canvas canvas,
    ui.Path path, {
    required double width,
    required Color color,
  }) {
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
      oldDelegate.offset != offset ||
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.track != track ||
      oldDelegate.color != color;
}

class _ProjectedRecordedTrack {
  _ProjectedRecordedTrack({
    required this.points,
    required this.start,
    required this.current,
    required this.headingDegrees,
  });

  _ProjectedRecordedTrack.empty()
    : points = const [],
      start = Offset.zero,
      current = Offset.zero,
      headingDegrees = null;

  /// Simplified track in pan-frame coordinates.
  final List<Offset> points;
  final Offset start;
  final Offset current;
  final double? headingDegrees;

  late final Rect bounds = () {
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }();

  late final ui.Path path = () {
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }();
}
