import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/pan_projection_frame.dart';
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
    // The snapshot's buildings are sorted once in [UrbanRenderCache.prepare];
    // filtering keeps that order, so no per-frame sort is needed.
    final buildings = [
      for (final area in _cache._sortedBuildings)
        if (MapRenderingBudget.areaMayBeVisible(area, bounds)) area,
    ];
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
    final offset = _cache._beginCamera(camera);
    final projectedBuildings = <_ProjectedBuilding>[];
    for (final indexed in buildings.indexed) {
      final area = indexed.$2;
      final footprint = _cache._frameFootprints.containsKey(area)
          ? _cache._frameFootprints[area]
          : _cache._frameFootprints[area] = _projectFootprint(
              area,
              camera,
              offset,
            );
      if (footprint == null) continue;
      // Snap each footprint's first corner to a whole screen pixel, exactly
      // as a fresh projection did; the frame geometry itself stays unsnapped
      // so the snap does not accumulate across pans.
      final origin = footprint.projected.first + offset;
      final translation =
          offset +
          Offset(
            origin.dx.roundToDouble() - origin.dx,
            origin.dy.roundToDouble() - origin.dy,
          );
      projectedBuildings.add(
        _ProjectedBuilding(
          footprint: footprint,
          translation: translation,
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

  /// Projects one footprint into the cache's pan frame.
  static _FrameFootprint? _projectFootprint(
    AreaFeature area,
    MapCamera camera,
    Offset offset,
  ) {
    final ring = _sanitized(area.ring);
    if (ring == null) return null;
    Offset project(LatLng point) =>
        PanProjectionFrame.project(camera, offset, point);
    return _FrameFootprint(
      projected: [for (final point in ring) project(point)],
      holes: [
        for (final hole in area.holes)
          if (_sanitized(hole) case final cleanHole?)
            [for (final point in cleanHole) project(point)],
      ],
    );
  }

  // Footprint validation formats every vertex and tests all edge pairs for
  // self-intersection. OSM features are immutable, so validate each ring once.
  static final Expando<_SanitizedRing> _sanitizedRings =
      Expando<_SanitizedRing>('wildbit-urban-footprint');

  static List<LatLng>? _sanitized(List<LatLng> ring) =>
      (_sanitizedRings[ring] ??= _SanitizedRing(
        StructureFootprint.sanitize(ring),
      )).points;
}

/// Per-camera cache owned by the map composition, rather than one depth
/// slice. Its internals stay library-private because only this layer paints
/// the projected footprint data.
class UrbanRenderCache {
  MapFeatureCollection? _source;
  List<AreaFeature> _sortedBuildings = const [];
  int? visibleBuildingsViewKey;
  List<AreaFeature>? visibleBuildings;
  int? projectedBuildingsViewKey;
  List<_ProjectedBuilding>? _projectedBuildings;
  // Footprints projected into the current pan frame, keyed by OSM feature.
  PanProjectionFrame? _frame;
  final Map<AreaFeature, _FrameFootprint?> _frameFootprints = {};

  void prepare(MapFeatureCollection source) {
    if (identical(_source, source)) return;
    _source = source;
    // A stable, deterministic draw/budget order for the whole snapshot. The
    // key used to be rebuilt (centroid + string) inside every comparison of
    // a sort that ran on each camera frame.
    final keyed = [
      for (final area in source.areas)
        if (area.kind == MapFeatureKind.building)
          (
            area: area,
            key:
                '${area.sourceId ?? ''}:'
                '${StructureFootprint.centroid(area.ring).latitude.toStringAsFixed(7)}',
          ),
    ]..sort((a, b) => a.key.compareTo(b.key));
    _sortedBuildings = List.unmodifiable([
      for (final entry in keyed) entry.area,
    ]);
    visibleBuildingsViewKey = null;
    visibleBuildings = null;
    projectedBuildingsViewKey = null;
    _projectedBuildings = null;
    _frameFootprints.clear();
  }

  /// Retains the OSM source identity but releases camera-dependent polygons.
  void clearTransient() {
    visibleBuildingsViewKey = null;
    visibleBuildings = null;
    projectedBuildingsViewKey = null;
    _projectedBuildings = null;
    _frame = null;
    _frameFootprints.clear();
  }

  /// Returns the translation from the footprint frame to [camera]'s screen,
  /// starting a new frame when needed.
  Offset _beginCamera(MapCamera camera) {
    final frame = _frame;
    if (frame == null || !frame.accepts(camera)) {
      _frame = PanProjectionFrame(camera);
      _frameFootprints.clear();
    }
    return _frame!.offsetFor(camera);
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

  static final Paint _shadowPaint = Paint()
    ..color = const Color(0x55312624)
    ..style = PaintingStyle.fill;
  static final Paint _wallPaint = Paint()
    ..color = const Color(0xFF6F5542)
    ..style = PaintingStyle.fill;
  static final Paint _roofPaint = Paint()
    ..color = const Color(0xFF8D694C)
    ..style = PaintingStyle.fill;

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
    final viewport = Offset.zero & size;
    final outline = Paint()
      ..color = const Color(0xFF3B302A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 + .4 * ((camera.zoom - 11) / 5).clamp(0.0, 1.0);
    for (var index = start; index < end; index++) {
      final building = projectedBuildings[index];
      final footprint = building.footprint;
      final translation = building.translation;
      if (!footprint.bounds
          .shift(translation)
          .inflate(8 * scale)
          .overlaps(viewport)) {
        continue;
      }
      final roof = footprint.roof;
      canvas.save();
      canvas.translate(translation.dx, translation.dy);
      // Walls and their shadow are the roof outline moved down (and right):
      // translate the canvas instead of rebuilding two paths per building.
      canvas.save();
      canvas.translate(2 * scale, extrusion + 2 * scale);
      canvas.drawPath(roof, _shadowPaint);
      canvas.translate(-2 * scale, -2 * scale);
      canvas.drawPath(roof, _wallPaint);
      canvas.restore();
      canvas.drawPath(roof, _roofPaint);
      canvas.drawPath(roof, outline);
      if (detail > 0) _paintRoofInset(canvas, footprint, detail);
      canvas.restore();
    }
  }

  static ui.Path _path(
    List<Offset> points, {
    List<List<Offset>> holes = const [],
  }) {
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
    _FrameFootprint footprint,
    double detail,
  ) {
    final projected = footprint.projected;
    if (projected.length < 3) return;
    canvas.save();
    canvas.clipPath(footprint.roof);
    canvas.drawPath(
      footprint.inset,
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
  _ProjectedBuilding({
    required this.footprint,
    required this.translation,
    required this.stableOrder,
  }) : foot = footprint.foot + translation;

  final _FrameFootprint footprint;

  /// Pan offset plus this footprint's whole-pixel snap.
  final Offset translation;

  /// Screen-space ground contact, used for depth ordering around Bit.
  final Offset foot;
  final int stableOrder;
}

/// A building footprint in pan-frame coordinates, with the paths painters
/// reuse until the next zoom or rotation.
class _FrameFootprint {
  _FrameFootprint({required this.projected, required this.holes})
    : foot = ProjectedDepthOrder.footprintAnchor(projected);

  final List<Offset> projected;
  final List<List<Offset>> holes;
  final Offset foot;

  late final ui.Path roof = _UrbanPainter._path(projected, holes: holes);
  late final Rect bounds = roof.getBounds();

  /// Roof ridge inset: the outline pulled 22% toward its vertex centroid.
  late final ui.Path inset = () {
    var center = Offset.zero;
    for (final point in projected) {
      center += point;
    }
    center /= projected.length.toDouble();
    final path = ui.Path();
    for (var i = 0; i < projected.length; i++) {
      final point = Offset.lerp(center, projected[i], .78)!;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }();
}

class _SanitizedRing {
  const _SanitizedRing(this.points);

  final List<LatLng>? points;
}
