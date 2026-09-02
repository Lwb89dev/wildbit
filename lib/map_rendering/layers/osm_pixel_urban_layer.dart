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
class OsmPixelUrbanLayer extends StatefulWidget {
  const OsmPixelUrbanLayer({
    super.key,
    required this.features,
    this.depthPivot,
    this.slice = ProjectedDepthSlice.all,
    this.renderCache,
  });

  final MapFeatureCollection features;
  final ValueListenable<LatLng?>? depthPivot;
  final ProjectedDepthSlice slice;

  /// Share this cache between the behind/in-front depth passes. Both passes
  /// use identical features and camera data, so projecting every footprint
  /// twice is pure CPU work with no visual benefit.
  final UrbanRenderCache? renderCache;

  @override
  State<OsmPixelUrbanLayer> createState() => _OsmPixelUrbanLayerState();
}

class _OsmPixelUrbanLayerState extends State<OsmPixelUrbanLayer> {
  final UrbanRenderCache _localCache = UrbanRenderCache();

  UrbanRenderCache get _cache => widget.renderCache ?? _localCache;

  @override
  void didUpdateWidget(covariant OsmPixelUrbanLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cache.prepare(widget.features);
  }

  @override
  Widget build(BuildContext context) {
    _cache.prepare(widget.features);
    final camera = MapCamera.of(context);
    final buildings = _visibleBuildings(camera);
    if (buildings.isEmpty) return const SizedBox.expand();
    final projectedBuildings = _projectBuildings(camera, buildings);
    if (widget.depthPivot != null) {
      return ValueListenableBuilder<LatLng?>(
        valueListenable: widget.depthPivot!,
        builder: (context, pivot, _) =>
            _buildLayer(camera, pivot, projectedBuildings),
      );
    }
    return _buildLayer(camera, null, projectedBuildings);
  }

  List<AreaFeature> _visibleBuildings(MapCamera camera) {
    // Buildings are orientation context, not the map's primary artwork. At
    // overview zooms they collapse into a noisy grey carpet, so roads and
    // trails carry the urban shape until the user is close enough to inspect
    // individual footprints. During a gesture keep a small stable sample
    // instead of removing the whole layer: this prevents buildings/refuges
    // from blinking out while the camera rotates or pans on a phone.
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      identityHashCode(widget.features),
      camera.zoom,
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      MapRenderingBudget.mapInteracting,
    );
    final cached = _cache.visibleBuildings;
    if (cached != null && _cache.visibleBuildingsViewKey == viewKey) {
      return cached;
    }
    if (camera.zoom < 15.5) {
      _cache.visibleBuildingsViewKey = viewKey;
      _cache.visibleBuildings = const [];
      return const [];
    }
    final buildings =
        widget.features.areas
            .where(
              (area) =>
                  area.kind == MapFeatureKind.building &&
                  MapRenderingBudget.areaMayBeVisible(area, bounds),
            )
            .toList(growable: false)
          ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    final limit = MapRenderingBudget.urbanPaintLimit();
    final result = buildings.length <= limit
        ? buildings
        : buildings.take(limit).toList(growable: false);
    _cache.visibleBuildingsViewKey = viewKey;
    _cache.visibleBuildings = List.unmodifiable(result);
    return _cache.visibleBuildings!;
  }

  Widget _buildLayer(
    MapCamera camera,
    LatLng? pivot,
    List<_ProjectedBuilding> projectedBuildings,
  ) {
    // Before the first GPS fix there is no meaningful depth pivot. Keep one
    // complete background pass and suppress the foreground duplicate.
    if (pivot == null && widget.slice == ProjectedDepthSlice.inFrontOfPivot) {
      return const SizedBox.expand();
    }
    final pivotBoundary = pivot == null
        ? null
        : ProjectedDepthOrder.firstInFrontIndex(
            projectedBuildings,
            camera.latLngToScreenOffset(pivot),
            (building) => building.foot,
          );
    final child = LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: CustomPaint(
          painter: _UrbanPainter(
            camera: camera,
            projectedBuildings: projectedBuildings,
            pivotBoundary: pivotBoundary,
            slice: widget.slice,
          ),
        ),
      ),
    );
    return IgnorePointer(child: child);
  }

  static String _sortKey(AreaFeature area) =>
      '${area.sourceId ?? ''}:'
      '${StructureFootprint.centroid(area.ring).latitude.toStringAsFixed(7)}';

  List<_ProjectedBuilding> _projectBuildings(
    MapCamera camera,
    List<AreaFeature> buildings,
  ) {
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      identityHashCode(buildings),
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
    final cached = _cache._projectedBuildings;
    if (cached != null && _cache.projectedBuildingsViewKey == viewKey) {
      return cached;
    }
    final projectedBuildings = <_ProjectedBuilding>[];
    for (final indexed in buildings.indexed) {
      final area = indexed.$2;
      final ring = StructureFootprint.sanitize(area.ring);
      if (ring == null) continue;
      final raw = [
        for (final point in ring) camera.latLngToScreenOffset(point),
      ];
      final rawHoles = [
        for (final hole in area.holes)
          if (StructureFootprint.sanitize(hole) case final cleanHole?)
            [for (final point in cleanHole) camera.latLngToScreenOffset(point)],
      ];
      final snapDelta = _snap(raw.first) - raw.first;
      final projected = [for (final point in raw) point + snapDelta];
      final projectedHoles = [
        for (final hole in rawHoles)
          [for (final point in hole) point + snapDelta],
      ];
      projectedBuildings.add(
        _ProjectedBuilding(
          projected: projected,
          holes: projectedHoles,
          foot: ProjectedDepthOrder.footprintAnchor(projected),
          stableOrder: indexed.$1,
        ),
      );
    }
    projectedBuildings.sort((a, b) {
      final depth = ProjectedDepthOrder.compare(
        firstFoot: a.foot,
        secondFoot: b.foot,
      );
      return depth != 0 ? depth : a.stableOrder.compareTo(b.stableOrder);
    });
    _cache.projectedBuildingsViewKey = viewKey;
    _cache._projectedBuildings = List.unmodifiable(projectedBuildings);
    return _cache._projectedBuildings!;
  }

  static Offset _snap(Offset point) =>
      Offset(point.dx.roundToDouble(), point.dy.roundToDouble());
}

/// Per-camera cache owned by the map composition, rather than one depth
/// slice. Its internals stay library-private because only this layer paints
/// the projected footprint data.
class UrbanRenderCache {
  MapFeatureCollection? _source;
  int? visibleBuildingsViewKey;
  List<AreaFeature>? visibleBuildings;
  int? projectedBuildingsViewKey;
  List<_ProjectedBuilding>? _projectedBuildings;

  void prepare(MapFeatureCollection source) {
    if (identical(_source, source)) return;
    _source = source;
    visibleBuildingsViewKey = null;
    visibleBuildings = null;
    projectedBuildingsViewKey = null;
    _projectedBuildings = null;
  }

  /// Retains the OSM source identity but releases camera-dependent polygons.
  void clearTransient() {
    visibleBuildingsViewKey = null;
    visibleBuildings = null;
    projectedBuildingsViewKey = null;
    _projectedBuildings = null;
  }
}

class _UrbanPainter extends CustomPainter {
  const _UrbanPainter({
    required this.camera,
    required this.projectedBuildings,
    required this.pivotBoundary,
    required this.slice,
  });

  final MapCamera camera;
  final List<_ProjectedBuilding> projectedBuildings;
  final int? pivotBoundary;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .35,
      max: 1.1,
    );
    final detail = MapRenderingBudget.mapInteracting
        ? 0.0
        : ((camera.zoom - 12) / 3).clamp(0.0, 1.0);
    final extrusion = (1.5 + 2.5 * detail) * scale;
    var start = 0;
    var end = projectedBuildings.length;
    final boundary = pivotBoundary;
    if (boundary != null) {
      switch (slice) {
        case ProjectedDepthSlice.all:
          break;
        case ProjectedDepthSlice.behindPivot:
          end = boundary;
        case ProjectedDepthSlice.inFrontOfPivot:
          start = boundary;
      }
    }
    for (var index = start; index < end; index++) {
      final building = projectedBuildings[index];
      final projected = building.projected;
      final projectedHoles = building.holes;
      final roof = _path(projected, holes: projectedHoles);
      if (!roof.getBounds().inflate(8 * scale).overlaps(Offset.zero & size)) {
        continue;
      }
      final wall = _path(
        [for (final point in projected) point.translate(0, extrusion)],
        holes: [
          for (final hole in projectedHoles)
            [for (final point in hole) point.translate(0, extrusion)],
        ],
      );
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
          ..strokeWidth = 1 + .4 * ((camera.zoom - 11) / 5).clamp(0.0, 1.0),
      );
      if (detail > 0) {
        _paintRoofInset(canvas, projected, detail, holes: projectedHoles);
      }
    }
  }

  ui.Path _path(List<Offset> points, {List<List<Offset>> holes = const []}) {
    final path = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    for (final hole in holes) {
      if (hole.length < 3) continue;
      path.moveTo(hole.first.dx, hole.first.dy);
      for (final point in hole.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    }
    return path;
  }

  void _paintRoofInset(
    Canvas canvas,
    List<Offset> projected,
    double detail, {
    List<List<Offset>> holes = const [],
  }) {
    if (projected.length < 3) return;
    canvas.save();
    canvas.clipPath(_path(projected, holes: holes));
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
    if (highlightStrength <= 0) {
      canvas.restore();
      return;
    }
    final highlight = Paint()
      ..color = const Color(
        0xFF403A34,
      ).withValues(alpha: .33 * highlightStrength)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < projected.length; i += 2) {
      canvas.drawLine(projected[i], projected[i + 1], highlight);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UrbanPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.projectedBuildings != projectedBuildings ||
      oldDelegate.pivotBoundary != pivotBoundary ||
      oldDelegate.slice != slice;
}

class _ProjectedBuilding {
  const _ProjectedBuilding({
    required this.projected,
    required this.holes,
    required this.foot,
    required this.stableOrder,
  });

  final List<Offset> projected;
  final List<List<Offset>> holes;
  final Offset foot;
  final int stableOrder;
}
