import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../composition/projected_depth_order.dart';
import '../performance/map_rendering_budget.dart';

/// Renders mapped linear barriers independently from navigable routes.
/// A fence/wall is never mistaken for a trail or road.
class OsmPixelBarrierLayer extends StatelessWidget {
  const OsmPixelBarrierLayer({
    super.key,
    required this.features,
    this.depthPivot,
    this.slice = ProjectedDepthSlice.all,
  });

  final MapFeatureCollection features;
  final ValueListenable<LatLng?>? depthPivot;
  final ProjectedDepthSlice slice;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final pivot = depthPivot;
    if (pivot == null || slice == ProjectedDepthSlice.all) {
      return _paint(camera, null);
    }
    return ValueListenableBuilder<LatLng?>(
      valueListenable: pivot,
      builder: (context, position, child) => _paint(camera, position),
    );
  }

  Widget _paint(MapCamera camera, LatLng? pivot) => RepaintBoundary(
    child: IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarrierPainter(
          camera: camera,
          features: features,
          pivot: pivot,
          slice: slice,
        ),
      ),
    ),
  );
}

class _BarrierPainter extends CustomPainter {
  const _BarrierPainter({
    required this.camera,
    required this.features,
    required this.pivot,
    required this.slice,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final LatLng? pivot;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    final pivotFoot = pivot == null
        ? null
        : camera.latLngToScreenOffset(pivot!);
    for (final line in features.lines) {
      if (line.kind != MapFeatureKind.barrier ||
          !MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds)) {
        continue;
      }
      final points = OsmLineProjector.projectSimplified(
        line,
        camera.latLngToScreenOffset,
        minimumDistancePixels: math.max(
          MapRenderingBudget.minLinePointDistancePixels,
          16 - camera.zoom,
        ),
      );
      if (points.length < 2) continue;
      final runs = _runsForSlice(points, pivotFoot);
      for (final run in runs) {
        if (run.length < 2) continue;
        _paintBarrier(
          canvas,
          run,
          line.metadata.barrierTag,
          line.metadata.hasConditionalAccess,
        );
      }
    }
  }

  List<List<Offset>> _runsForSlice(List<Offset> points, Offset? pivotFoot) {
    // Before Bit has published an anchor, keep one complete barrier pass. The
    // second (foreground) pass intentionally paints nothing until then.
    if (pivotFoot == null) {
      return slice == ProjectedDepthSlice.inFrontOfPivot ? const [] : [points];
    }
    if (slice == ProjectedDepthSlice.all) return [points];

    final runs = <List<Offset>>[];
    List<Offset>? current;
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final belongs = ProjectedDepthOrder.belongsToSlice(
        objectFoot: midpoint,
        pivotFoot: pivotFoot,
        slice: slice,
      );
      if (!belongs) {
        if (current != null && current.length > 1) runs.add(current);
        current = null;
        continue;
      }
      current ??= <Offset>[start];
      current.add(end);
    }
    if (current != null && current.length > 1) runs.add(current);
    return runs;
  }

  void _paintBarrier(
    Canvas canvas,
    List<Offset> points,
    String? barrier,
    bool conditional,
  ) {
    final color = conditional
        ? const Color(0xFFE4A43B)
        : switch (barrier) {
            'hedge' => const Color(0xFF3E6B3C),
            'wall' || 'retaining_wall' => const Color(0xFF5B5148),
            'gate' || 'lift_gate' => const Color(0xFF9D3E32),
            _ => const Color(0xFF775B3D),
          };
    final width = switch (barrier) {
      'wall' || 'retaining_wall' => 3.2,
      'hedge' => 3.8,
      _ => 2.0,
    };
    if (barrier == 'fence' ||
        barrier == 'cable_barrier' ||
        barrier == 'chain') {
      _paintDashed(canvas, points, color: color, width: width);
    } else {
      _paintSolid(canvas, points, color: color, width: width);
    }
  }

  void _paintSolid(
    Canvas canvas,
    List<Offset> points, {
    required Color color,
    required double width,
  }) {
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
        ..strokeJoin = StrokeJoin.bevel
        ..isAntiAlias = false,
    );
  }

  void _paintDashed(
    Canvas canvas,
    List<Offset> points, {
    required Color color,
    required double width,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = false;
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final delta = points[index + 1] - start;
      final length = delta.distance;
      if (length <= 0) continue;
      final direction = delta / length;
      for (var distance = 0.0; distance < length; distance += 8) {
        final end = math.min(distance + 4, length);
        canvas.drawLine(
          start + direction * distance,
          start + direction * end,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarrierPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.features != features ||
      oldDelegate.pivot != pivot ||
      oldDelegate.slice != slice;
}
