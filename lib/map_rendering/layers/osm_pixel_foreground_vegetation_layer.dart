import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/map_geometry_rules.dart';
import '../composition/osm_line_projector.dart';
import '../composition/projected_depth_order.dart';
import '../performance/map_rendering_budget.dart';

/// Deterministic foreground vegetation generated from real area polygons.
/// It is decorative only: no generated sprite is used as a navigational POI.
class OsmPixelForegroundVegetationLayer extends StatefulWidget {
  const OsmPixelForegroundVegetationLayer({
    super.key,
    required this.features,
    this.depthPivot,
    this.slice = ProjectedDepthSlice.all,
    this.renderCache,
  });

  final MapFeatureCollection features;

  /// Bit's interpolated ground anchor. Low vegetation follows the same
  /// screen-space depth rule as trees, buildings and POIs.
  final ValueListenable<LatLng?>? depthPivot;
  final ProjectedDepthSlice slice;

  /// Shared by the background and foreground depth slices around Bit. The
  /// two painters differ only in their final depth range, not in candidate
  /// generation, projection or geographic sort order.
  final ForegroundVegetationRenderCache? renderCache;

  @override
  State<OsmPixelForegroundVegetationLayer> createState() =>
      _OsmPixelForegroundVegetationLayerState();
}

class _OsmPixelForegroundVegetationLayerState
    extends State<OsmPixelForegroundVegetationLayer> {
  static const _candidateLimit = 180;
  static const _assets = [
    'assets/map/mock/objects/shrub_round.png',
    'assets/map/mock/objects/shrub_wide.png',
    'assets/map/mock/objects/shrub_riverside.png',
  ];
  static const _atlasRects = [
    Rect.fromLTWH(0, 0, 16, 16),
    Rect.fromLTWH(16, 0, 24, 16),
    Rect.fromLTWH(40, 0, 16, 16),
  ];
  static Future<_VegetationSpriteBundle>? _sharedSpriteBundle;

  List<ui.Image> _images = const [];
  ui.Image? _spriteAtlas;
  final ForegroundVegetationRenderCache _localCache =
      ForegroundVegetationRenderCache();
  Future<void>? _loading;

  ForegroundVegetationRenderCache get _cache =>
      widget.renderCache ?? _localCache;

  @override
  void initState() {
    super.initState();
    _refreshCache();
  }

  @override
  void didUpdateWidget(covariant OsmPixelForegroundVegetationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshCache();
    _ensureImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  void _ensureImages() {
    if (_cache._candidates.isEmpty) return;
    if (_images.isEmpty) _loading ??= _loadImages();
  }

  void _refreshCache() {
    final signature = _signature(widget.features);
    if (_cache.matches(widget.features, signature)) return;
    _cache._reset(widget.features, signature, _composeCandidates());
  }

  Future<void> _loadImages() async {
    try {
      final bundle = _sharedSpriteBundle ??= _buildSharedSpriteBundle();
      final sprites = await bundle;
      if (mounted) {
        setState(() {
          _images = sprites.images;
          _spriteAtlas = sprites.atlas;
        });
      }
    } catch (_) {
      _sharedSpriteBundle = null;
      // Decorative assets must never make the navigational map unavailable.
    } finally {
      _loading = null;
    }
  }

  Future<_VegetationSpriteBundle> _buildSharedSpriteBundle() async {
    final images = List<ui.Image>.unmodifiable(
      await Future.wait(_assets.map(_resolveImage)),
    );
    final atlas = await _composeSpriteAtlas(images);
    return _VegetationSpriteBundle(images: images, atlas: atlas);
  }

  Future<ui.Image> _resolveImage(String asset) =>
      MapVisualAssetWarmup.resolveImage(context, asset);

  Future<ui.Image> _composeSpriteAtlas(List<ui.Image> images) async {
    // The three authored shrubs have different native widths. Preserve those
    // exact proportions in one 56x16 atlas so a foreground pass can issue a
    // single drawAtlas command while retaining its existing size rules.
    const atlasSize = Size(56, 16);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final target = _atlasRects[index];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        target,
        paint,
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        atlasSize.width.toInt(),
        atlasSize.height.toInt(),
      );
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final projectedCandidates = _projectForCamera(camera);
    Widget paintForPivot(LatLng? pivot) {
      // Before the first GPS fix, retain exactly one complete pass and avoid
      // duplicating every shrub in the foreground slice.
      if (pivot == null && widget.slice == ProjectedDepthSlice.inFrontOfPivot) {
        return const SizedBox.expand();
      }
      final pivotBoundary = pivot == null
          ? null
          : ProjectedDepthOrder.firstInFrontIndex(
              projectedCandidates,
              camera.latLngToScreenOffset(pivot),
              (candidate) => candidate.foot,
            );
      return IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => RepaintBoundary(
            child: CustomPaint(
              size: constraints.biggest,
              painter: _VegetationPainter(
                camera: camera,
                projectedCandidates: projectedCandidates,
                images: _images,
                spriteAtlas: _spriteAtlas,
                pivotBoundary: pivotBoundary,
                slice: widget.slice,
              ),
            ),
          ),
        ),
      );
    }

    final depthPivot = widget.depthPivot;
    return depthPivot == null
        ? paintForPivot(null)
        : ValueListenableBuilder<LatLng?>(
            valueListenable: depthPivot,
            builder: (context, pivot, _) => paintForPivot(pivot),
          );
  }

  List<_ProjectedVegetationPoint> _projectForCamera(MapCamera camera) {
    _refreshCache();
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      _cache._featureSignature,
      camera.center.latitude,
      camera.center.longitude,
      camera.zoom,
      camera.rotation,
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      MapRenderingBudget.decorativeQuality,
    );
    final cached = _cache._projectedCandidates;
    if (cached != null && _cache._projectedViewKey == viewKey) return cached;
    final budgeted = MapRenderingBudget.stableDecorativeSubset(
      _cache._candidates,
      count: MapRenderingBudget.decorativeLodCount(
        camera.zoom,
        overview: 56,
        close: _cache._candidates.length,
      ),
      rank: (point) =>
          point.position.latitude.hashCode ^ point.position.longitude.hashCode,
    );
    final projected =
        [
          for (final point in budgeted)
            _ProjectedVegetationPoint(
              point: point,
              foot: camera.latLngToScreenOffset(point.position),
            ),
        ]..sort((a, b) {
          final depth = ProjectedDepthOrder.compare(
            firstFoot: a.foot,
            secondFoot: b.foot,
          );
          if (depth != 0) return depth;
          final latitude = a.point.position.latitude.compareTo(
            b.point.position.latitude,
          );
          if (latitude != 0) return latitude;
          return a.point.position.longitude.compareTo(
            b.point.position.longitude,
          );
        });
    _cache._projectedViewKey = viewKey;
    _cache._projectedCandidates = List.unmodifiable(projected);
    return _cache._projectedCandidates!;
  }

  List<_VegetationPoint> _composeCandidates() {
    final poiObstacles = [
      for (final poi in widget.features.pois)
        if (poi.type != PoiType.tree) poi.position,
    ];
    final poiObstacleIndex = MapPointAnchorIndex(poiObstacles);
    final areas = widget.features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.forest ||
              area.kind == MapFeatureKind.meadow ||
              area.kind == MapFeatureKind.park,
        )
        .toList(growable: false);
    final result = <_VegetationPoint>[];
    if (areas.isNotEmpty) {
      // Give every polygon a fair share. A large first polygon must not starve
      // smaller parks that enter the viewport later.
      final perArea = math.max(8, (_candidateLimit / areas.length).ceil());
      for (final area in areas) {
        if (result.length >= _candidateLimit) break;
        result.addAll(
          _sample(
            area,
            math.min(perArea, _candidateLimit - result.length),
            poiObstacleIndex,
          ),
        );
      }
    }
    if (result.length < _candidateLimit) {
      result.addAll(
        _sampleNearTrees(_candidateLimit - result.length, poiObstacleIndex),
      );
    }
    return List.unmodifiable(result);
  }

  List<_VegetationPoint> _sample(
    AreaFeature area,
    int remaining,
    MapPointAnchorIndex poiObstacleIndex,
  ) {
    if (area.ring.length < 3 || remaining <= 0) return const [];
    var south = area.ring.first.latitude;
    var north = south;
    var west = area.ring.first.longitude;
    var east = west;
    for (final point in area.ring.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    final random = math.Random(_seed(area));
    final localAreas = MapGeometryRules.areasNearArea(
      area,
      widget.features.areas,
    );
    final localLines = MapGeometryRules.linesNearArea(
      area,
      widget.features.lines,
    );
    final result = <_VegetationPoint>[];
    for (
      var attempt = 0;
      attempt < remaining * 6 && result.length < remaining;
      attempt++
    ) {
      final position = LatLng(
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      );
      if (!MapGeometryRules.pointInArea(position, area) ||
          MapGeometryRules.insideAnyWater(position, localAreas) ||
          _blockedByStructureInAreas(position, localAreas) ||
          MapGeometryRules.nearAnyLine(position, localLines) ||
          poiObstacleIndex.containsNear(position)) {
        continue;
      }
      if (random.nextDouble() > MapRenderingBudget.biomeDensity(area.kind)) {
        continue;
      }
      final edgeScale =
          MapGeometryRules.nearPolygonBoundary(
            position,
            area.ring,
            thresholdDegrees: .0003,
          )
          ? .7
          : 1.0;
      result.add(_VegetationPoint(position, random.nextInt(3), edgeScale));
    }
    return result;
  }

  List<_VegetationPoint> _sampleNearTrees(
    int remaining,
    MapPointAnchorIndex poiObstacleIndex,
  ) {
    final trees = widget.features.pois
        .where((poi) => poi.type == PoiType.tree)
        .toList(growable: false);
    final result = <_VegetationPoint>[];
    for (var i = 0; i < trees.length && result.length < remaining; i++) {
      final tree = trees[i];
      final seed = tree.id.hashCode ^ (i * 7919);
      final latOffset = (((seed.abs() % 100) / 100) - .5) * .00065;
      final lonOffset = ((((seed ~/ 101).abs() % 100) / 100) - .5) * .00065;
      final point = LatLng(
        tree.position.latitude + latOffset,
        tree.position.longitude + lonOffset,
      );
      if (MapGeometryRules.insideAnyWater(point, widget.features.areas) ||
          _blockedByStructure(point) ||
          poiObstacleIndex.containsNear(point) ||
          MapGeometryRules.nearAnyLine(
            point,
            widget.features.lines,
            thresholdDegrees: .00022,
          )) {
        continue;
      }
      result.add(_VegetationPoint(point, seed.abs() % 3, .86));
    }
    return result;
  }

  bool _blockedByStructure(LatLng point) {
    return _blockedByStructureInAreas(point, widget.features.areas);
  }

  bool _blockedByStructureInAreas(LatLng point, Iterable<AreaFeature> areas) {
    return MapGeometryRules.insideOrNearAnyAreaKind(
      point,
      areas,
      MapFeatureKind.building,
    );
  }

  int _seed(AreaFeature area) {
    var value = area.sourceId?.hashCode ?? area.ring.length;
    for (final point in area.ring) {
      value = value * 31 + point.latitude.hashCode;
      value = value * 31 + point.longitude.hashCode;
    }
    return value;
  }

  int _signature(MapFeatureCollection features) => Object.hash(
    Object.hashAll(features.areas.map((area) => area.sourceId ?? _seed(area))),
    Object.hashAll(
      features.lines.map((line) => OsmLineProjector.seedFor(line)),
    ),
    Object.hashAll(features.pois.map((poi) => poi.id)),
  );
}

/// Composition-owned cache for low vegetation. It avoids a second candidate
/// sampling and camera projection pass solely because Bit splits the paint
/// order in two.
class ForegroundVegetationRenderCache {
  MapFeatureCollection? _source;
  int? _featureSignature;
  List<_VegetationPoint> _candidates = const [];
  int? _projectedViewKey;
  List<_ProjectedVegetationPoint>? _projectedCandidates;

  bool matches(MapFeatureCollection source, int signature) =>
      identical(_source, source) && _featureSignature == signature;

  void _reset(
    MapFeatureCollection source,
    int signature,
    List<_VegetationPoint> candidates,
  ) {
    _source = source;
    _featureSignature = signature;
    _candidates = candidates;
    _projectedViewKey = null;
    _projectedCandidates = null;
  }

  /// Candidate placement is deterministic and comparatively small. Release
  /// the potentially larger screen-space projection when Android asks the
  /// process to trim memory, then rebuild it from the same candidates.
  void clearTransient() {
    _projectedViewKey = null;
    _projectedCandidates = null;
  }
}

class _VegetationSpriteBundle {
  const _VegetationSpriteBundle({required this.images, required this.atlas});

  final List<ui.Image> images;
  final ui.Image atlas;
}

class _VegetationPoint {
  const _VegetationPoint(this.position, this.variant, this.scaleMultiplier);

  final LatLng position;
  final int variant;
  final double scaleMultiplier;
}

class _ProjectedVegetationPoint {
  const _ProjectedVegetationPoint({required this.point, required this.foot});

  final _VegetationPoint point;
  final Offset foot;
}

class _VegetationPainter extends CustomPainter {
  const _VegetationPainter({
    required this.camera,
    required this.projectedCandidates,
    required this.images,
    required this.spriteAtlas,
    required this.pivotBoundary,
    required this.slice,
  });

  final MapCamera camera;
  final List<_ProjectedVegetationPoint> projectedCandidates;
  final List<ui.Image> images;
  final ui.Image? spriteAtlas;
  final int? pivotBoundary;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    // Projection and ordering belong to the camera and are cached by the
    // state object. A GPS fix only changes Bit's pivot, so use the already
    // sorted anchors to form the two occlusion slices.
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .35,
      max: 1.0,
    );
    final paint = Paint()..filterQuality = FilterQuality.none;
    var start = 0;
    var end = projectedCandidates.length;
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
    final atlas = spriteAtlas;
    if (atlas != null) {
      _paintAtlasBatch(canvas, size, start, end, atlas, scale, paint);
      return;
    }
    for (var index = start; index < end; index++) {
      final projected = projectedCandidates[index];
      final point = projected.point;
      final foot = projected.foot;
      final dimension = 25 * scale * point.scaleMultiplier;
      if (foot.dx < -dimension ||
          foot.dy < -dimension ||
          foot.dx > size.width + dimension ||
          foot.dy > size.height + dimension) {
        continue;
      }
      if (images.isEmpty) {
        canvas.drawCircle(
          foot.translate(0, -dimension * .32),
          dimension * .3,
          Paint()..color = const Color(0xFF4D7C35),
        );
        continue;
      }
      final image = images[point.variant % images.length];
      final imageScale = math.min(
        dimension / image.width,
        dimension / image.height,
      );
      final width = image.width * imageScale;
      final height = image.height * imageScale;
      final target = Rect.fromLTWH(
        foot.dx - width / 2,
        foot.dy - height,
        width,
        height,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        target,
        paint,
      );
    }
  }

  void _paintAtlasBatch(
    Canvas canvas,
    Size size,
    int start,
    int end,
    ui.Image atlas,
    double scale,
    Paint paint,
  ) {
    final transforms = <ui.RSTransform>[];
    final sourceRects = <Rect>[];
    final viewport = Offset.zero & size;
    for (var index = start; index < end; index++) {
      final projected = projectedCandidates[index];
      final point = projected.point;
      final foot = projected.foot;
      final dimension = 25 * scale * point.scaleMultiplier;
      if (foot.dx < -dimension ||
          foot.dy < -dimension ||
          foot.dx > size.width + dimension ||
          foot.dy > size.height + dimension) {
        continue;
      }
      final atlasRects = _OsmPixelForegroundVegetationLayerState._atlasRects;
      final variant = point.variant % atlasRects.length;
      final source = atlasRects[variant];
      final imageScale = math.min(
        dimension / source.width,
        dimension / source.height,
      );
      transforms.add(
        ui.RSTransform.fromComponents(
          rotation: 0,
          scale: imageScale,
          anchorX: source.width / 2,
          anchorY: source.height,
          translateX: foot.dx,
          translateY: foot.dy,
        ),
      );
      sourceRects.add(source);
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(
      atlas,
      transforms,
      sourceRects,
      null,
      BlendMode.srcOver,
      viewport,
      paint,
    );
  }

  @override
  bool shouldRepaint(_VegetationPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.projectedCandidates != projectedCandidates ||
      oldDelegate.images != images ||
      oldDelegate.spriteAtlas != spriteAtlas ||
      oldDelegate.pivotBoundary != pivotBoundary ||
      oldDelegate.slice != slice;
}
