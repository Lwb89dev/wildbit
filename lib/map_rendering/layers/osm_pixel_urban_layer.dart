import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/projected_depth_order.dart';
import '../composition/structure_footprint.dart';
import '../performance/map_rendering_budget.dart';

/// A deliberately quiet urban backdrop. Buildings provide orientation without
/// turning the map into a grey raster block or competing with trails.
class OsmPixelUrbanLayer extends StatelessWidget {
  const OsmPixelUrbanLayer({
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
    if (depthPivot != null) {
      return ValueListenableBuilder<LatLng?>(
        valueListenable: depthPivot!,
        builder: (context, pivot, _) => _buildLayer(camera, pivot),
      );
    }
    return _buildLayer(camera, null);
  }

  Widget _buildLayer(MapCamera camera, LatLng? pivot) {
    // Before the first GPS fix there is no meaningful depth pivot. Keep one
    // complete background pass and suppress the foreground duplicate.
    if (pivot == null && slice == ProjectedDepthSlice.inFrontOfPivot) {
      return const SizedBox.expand();
    }
    final buildings = features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.building &&
              MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds),
        )
        .toList(growable: false)
      ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    if (buildings.isEmpty) return const SizedBox.expand();
    final limited = buildings.length <= 240
        ? buildings
        : buildings.take(240).toList(growable: false);
    final child = LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: CustomPaint(
          painter: _UrbanPainter(
            camera: camera,
            buildings: limited,
            depthPivot: pivot,
            slice: slice,
          ),
        ),
      ),
    );
    return IgnorePointer(child: child);
  }

  static String _sortKey(AreaFeature area) =>
      (area.sourceId ?? '') +
      ':' +
      StructureFootprint.centroid(area.ring).latitude.toStringAsFixed(7);
}

class _UrbanPainter extends CustomPainter {
  const _UrbanPainter({
    required this.camera,
    required this.buildings,
    required this.depthPivot,
    required this.slice,
  });

  final MapCamera camera;
  final List<AreaFeature> buildings;
  final LatLng? depthPivot;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .35,
      max: 1.1,
    );
    final detail = ((camera.zoom - 12) / 3).clamp(0.0, 1.0);
    final extrusion = (1.5 + 2.5 * detail) * scale;
    final pivotFoot = depthPivot == null
        ? null
        : camera.latLngToScreenOffset(depthPivot!);
    for (final area in buildings) {
      final ring = StructureFootprint.sanitize(area.ring);
      if (ring == null) continue;
      final raw = [
        for (final point in ring) camera.latLngToScreenOffset(point),
      ];
      if (pivotFoot != null &&
          !ProjectedDepthOrder.belongsToSlice(
            objectFoot: camera.latLngToScreenOffset(
              StructureFootprint.centroid(ring),
            ),
            pivotFoot: pivotFoot,
            slice: slice,
          )) {
        continue;
      }
      // Snap the polygon as one rigid object. Snapping every vertex
      // independently changed its silhouette at fractional zoom values.
      final snapDelta = _snap(raw.first) - raw.first;
      final projected = [for (final point in raw) point + snapDelta];
      final roof = _path(projected);
      final wall = _path([
        for (final point in projected) point.translate(0, extrusion),
      ]);
      canvas.drawPath(
        wall.shift(Offset(2 * scale, 2 * scale)),
        Paint()
          ..color = const Color(0x55312624)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        wall,
        Paint()
          ..color = const Color(0xFF6F5542)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        roof,
        Paint()
          ..color = const Color(0xFF8D694C)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        roof,
        Paint()
          ..color = const Color(0xFF3B302A)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              1 + .4 * ((camera.zoom - 11) / 5).clamp(0.0, 1.0),
      );
      if (detail > 0) {
        _paintRoofInset(canvas, projected, detail);
      }
    }
  }

  Offset _snap(Offset point) =>
      Offset(point.dx.roundToDouble(), point.dy.roundToDouble());

  ui.Path _path(List<Offset> points) {
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  void _paintRoofInset(
    Canvas canvas,
    List<Offset> projected,
    double detail,
  ) {
    if (projected.length < 3) return;
    var center = Offset.zero;
    for (final point in projected) {
      center += point;
    }
    center /= projected.length.toDouble();
    final inset = ui.Path();
    for (var i = 0; i < projected.length; i++) {
      final point = Offset.lerp(center, projected[i], .78)!;
      if (i == 0) {
        inset.moveTo(point.dx, point.dy);
      } else {
        inset.lineTo(point.dx, point.dy);
      }
    }
    inset.close();
    canvas.drawPath(
      inset,
      Paint()
        ..color = const Color(0xFF3E3934).withValues(alpha: .4 * detail)
        ..style = PaintingStyle.fill,
    );
    final highlightStrength = ((camera.zoom - 12) / 4).clamp(0.0, 1.0);
    if (highlightStrength <= 0) return;
    final highlight = Paint()
      ..color = const Color(0xFF403A34).withValues(
        alpha: .33 * highlightStrength,
      )
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < projected.length; i += 2) {
      canvas.drawLine(projected[i], projected[i + 1], highlight);
    }
  }

  @override
  bool shouldRepaint(_UrbanPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.buildings != buildings ||
      oldDelegate.depthPivot != depthPivot ||
      oldDelegate.slice != slice;
}
