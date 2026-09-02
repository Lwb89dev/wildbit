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

/// Composes tall trees and low rocks in one geographic depth pass.
///
/// Keeping both object classes in the same stable candidate set prevents the
/// old whole-layer occlusion: a tree no longer hides every rock merely because
/// its layer was painted later. A forest polygon still describes land cover,
/// not exact tree positions; generated accents are deterministic per polygon.
class OsmPixelTreeLayer extends StatefulWidget {
  const OsmPixelTreeLayer({
    super.key,
    required this.features,
    this.depthPivot,
    this.middleChild,
  });

  final MapFeatureCollection features;

  /// Interpolated ground anchor of Bit, used after camera projection.
  final ValueListenable<LatLng?>? depthPivot;

  /// Actor painted between background and foreground object slices.
  final Widget? middleChild;

  @override
  State<OsmPixelTreeLayer> createState() => _OsmPixelTreeLayerState();
}

class _OsmPixelTreeLayerState extends State<OsmPixelTreeLayer> {
  // Candidates are richer than the paint budget. This prevents a large OSM
  // forest loaded first from starving smaller polygons while keeping the
  // number of sprites actually drawn bounded by the LOD budget below.
  static const _treeCandidateLimit = 520;
  static const _treePaintLimit = 300;
  // Explicit-tree POIs are decorative too. Keep a generous close-up budget,
  // but prevent a dense city/forest import from turning every camera tick
  // into thousands of image draws.
  static const _mappedTreePaintLimit = 420;
  // Individual OSM tree nodes can be extremely dense in a surveyed park.
  // They are visual context, not navigational evidence, so retain a stable
  // representative candidate set before the per-camera LOD budget is chosen.
  // This bounds both memory and projection work without affecting trails,
  // water, bridges or safety POIs.
  static const _mappedTreeCandidateLimit = 1200;
  static const _treeAssets = [
    'assets/map/mock/objects/tree_deciduous_s.png',
    'assets/map/mock/objects/tree_conifer.png',
    'assets/map/mock/objects/tree_deciduous_l.png',
  ];
  static const _rockAsset = 'assets/map/mock/structures/boulder.png';
  static Future<_TreeSpriteBundle>? _sharedSpriteBundle;

  List<ui.Image> _treeImages = const [];
  ui.Image? _rockImage;
  ui.Image? _spriteAtlas;
  List<_TreePaintItem> _mappedTrees = const [];
  List<_GeneratedTree> _generatedTrees = const [];
  List<_GeneratedRock> _generatedRocks = const [];
  List<_ForegroundPaintItem>? _projectedItems;
  int? _projectedViewKey;
  late int _featureSignature;
  Future<void>? _loading;

  @override
  void initState() {
    super.initState();
    _featureSignature = _signature(widget.features);
    _rebuildCandidates();
  }

  @override
  void didUpdateWidget(covariant OsmPixelTreeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.features);
    if (signature == _featureSignature) return;
    _featureSignature = signature;
    _projectedItems = null;
    _projectedViewKey = null;
    _rebuildCandidates();
    _ensureImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  void _ensureImages() {
    if (_mappedTrees.isEmpty &&
        _generatedTrees.isEmpty &&
        _generatedRocks.isEmpty) {
      return;
    }
    if (_treeImages.isEmpty || _rockImage == null) {
      _loading ??= _loadImages();
    }
  }

  Future<void> _loadImages() async {
    try {
      final bundle = _sharedSpriteBundle ??= _buildSharedSpriteBundle();
      final sprites = await bundle;
      if (mounted) {
        setState(() {
          _treeImages = sprites.trees;
          _rockImage = sprites.rock;
          _spriteAtlas = sprites.atlas;
        });
      }
    } catch (_) {
      // A failed future must not poison a later mount after transient asset
      // pressure; the next state can attempt the small shared atlas again.
      _sharedSpriteBundle = null;
      // Optional artwork must not make the map unavailable.
    } finally {
      _loading = null;
    }
  }

  Future<_TreeSpriteBundle> _buildSharedSpriteBundle() async {
    final images = await Future.wait([
      ..._treeAssets.map(_resolveImage),
      _resolveImage(_rockAsset),
    ]);
    final trees = List<ui.Image>.unmodifiable(images.take(_treeAssets.length));
    final rock = images.last;
    // All foreground objects share one small atlas. A dense forest used to
    // issue a separate drawImageRect command for each tree; batching the
    // identical 32-bit sprites into drawAtlas keeps their geographic depth
    // order but considerably lowers raster-thread command overhead.
    final atlas = await _composeSpriteAtlas(trees, rock);
    return _TreeSpriteBundle(trees: trees, rock: rock, atlas: atlas);
  }

  Future<ui.Image> _resolveImage(String asset) =>
      MapVisualAssetWarmup.resolveImage(context, asset);

  Future<ui.Image> _composeSpriteAtlas(
    List<ui.Image> trees,
    ui.Image rock,
  ) async {
    // Three 32x48 tree frames plus a 24x22 pre-scaled boulder.  The boulder
    // is resampled once here so every atlas entry can use one uniform
    // RSTransform scale without altering its established silhouette.
    const atlasSize = Size(144, 48);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (var index = 0; index < trees.length; index++) {
      final image = trees[index];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(index * 32.0, 0, 32, 48),
        paint,
      );
    }
    canvas.drawImageRect(
      rock,
      Rect.fromLTWH(0, 0, rock.width.toDouble(), rock.height.toDouble()),
      const Rect.fromLTWH(96, 0, 24, 22),
      paint,
    );
    // Preserve the previous deterministic left/right variation without an
    // extra draw call for every odd rock at paint time.
    canvas.save();
    canvas.translate(144, 0);
    canvas.scale(-1, 1);
    canvas.drawImageRect(
      rock,
      Rect.fromLTWH(0, 0, rock.width.toDouble(), rock.height.toDouble()),
      const Rect.fromLTWH(0, 0, 24, 22),
      paint,
    );
    canvas.restore();
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
    final pivot = widget.depthPivot;
    if (pivot == null || widget.middleChild == null) {
      return _buildScene(camera, null);
    }
    return ValueListenableBuilder<LatLng?>(
      valueListenable: pivot,
      child: widget.middleChild,
      builder: (context, position, middleChild) =>
          _buildScene(camera, position, middleChild: middleChild),
    );
  }

  Widget _buildScene(MapCamera camera, LatLng? pivot, {Widget? middleChild}) {
    // Project and depth-sort once per camera update. The three occlusion
    // slices below reuse this immutable list, avoiding duplicate geographic
    // projections and full sorts during every frame.
    final projectedItems = _projectItemsForCamera(camera);
    final pivotBoundary = pivot == null
        ? null
        : ProjectedDepthOrder.firstInFrontIndex(
            projectedItems,
            camera.latLngToScreenOffset(pivot),
            (item) => item.foot,
          );
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: middleChild == null
            ? _paintSlice(camera, projectedItems, null, ProjectedDepthSlice.all)
            : pivot == null
            // Bit must be mounted before it can publish its first interpolated
            // ground anchor. Until then, keep all objects behind him.
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _paintSlice(
                    camera,
                    projectedItems,
                    null,
                    ProjectedDepthSlice.all,
                  ),
                  middleChild,
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _paintSlice(
                    camera,
                    projectedItems,
                    pivotBoundary,
                    ProjectedDepthSlice.behindPivot,
                  ),
                  middleChild,
                  _paintSlice(
                    camera,
                    projectedItems,
                    pivotBoundary,
                    ProjectedDepthSlice.inFrontOfPivot,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _paintSlice(
    MapCamera camera,
    List<_ForegroundPaintItem> items,
    int? pivotBoundary,
    ProjectedDepthSlice slice,
  ) => RepaintBoundary(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _ForegroundObjectPainter(
          camera: camera,
          items: items,
          treeImages: _treeImages,
          rockImage: _rockImage,
          spriteAtlas: _spriteAtlas,
          pivotBoundary: pivotBoundary,
          slice: slice,
        ),
      ),
    ),
  );

  List<_ForegroundPaintItem> _projectItems(MapCamera camera) {
    // Do not pre-filter by geographic point. A sprite anchored just outside
    // the viewport can still overlap it; target-rect clipping in the painter
    // keeps that edge behaviour stable during zoom.
    final generatedTreeSubset = _decorativePrefix(
      _generatedTrees,
      MapRenderingBudget.decorativeLodCount(
        camera.zoom,
        overview: 96,
        close: math.min(
          _generatedTrees.length,
          _OsmPixelTreeLayerState._treePaintLimit,
        ),
      ),
    );
    final generatedRockSubset = _decorativePrefix(
      _generatedRocks,
      // Rocks use the same quantised bands as trees.  A smooth count here
      // used to remove/add one rock for every fractional zoom tick, which
      // looked like flicker on phone pinch gestures.
      MapRenderingBudget.decorativeLodCount(
        camera.zoom,
        overview: 24,
        close: _generatedRocks.length,
      ),
    );
    // Individual OSM tree nodes remain eligible at every zoom.  Previously
    // they were all dropped below 15.5, creating a conspicuous pop when a
    // user zoomed out of a mapped grove.  The same deterministic LOD budget
    // used for generated forests keeps overview views cheap while preserving
    // a stable representative canopy.
    final mappedTreeSubset = _decorativePrefix(
      _mappedTrees,
      MapRenderingBudget.decorativeLodCount(
        camera.zoom,
        overview: 32,
        close: math.min(
          _mappedTrees.length,
          _OsmPixelTreeLayerState._mappedTreePaintLimit,
        ),
      ),
    );
    final items = <_ForegroundPaintItem>[
      for (final tree in mappedTreeSubset)
        _ForegroundPaintItem.tree(
          tree.position,
          tree.seed,
          tree.scaleMultiplier,
          camera.latLngToScreenOffset(tree.position),
        ),
      for (final tree in generatedTreeSubset)
        _ForegroundPaintItem.tree(
          tree.position,
          tree.seed,
          tree.scaleMultiplier,
          camera.latLngToScreenOffset(tree.position),
        ),
      for (final rock in generatedRockSubset)
        _ForegroundPaintItem.rock(
          rock.position,
          rock.seed,
          camera.latLngToScreenOffset(rock.position),
        ),
    ];
    items.sort((a, b) {
      final depth = ProjectedDepthOrder.compare(
        firstFoot: a.foot,
        secondFoot: b.foot,
      );
      if (depth != 0) return depth;
      final kind = a.kind.index.compareTo(b.kind.index);
      return kind != 0 ? kind : a.seed.compareTo(b.seed);
    });
    return items;
  }

  List<T> _decorativePrefix<T>(List<T> ranked, int count) {
    if (count <= 0 || ranked.isEmpty) return const [];
    if (count >= ranked.length) return ranked;
    return ranked.sublist(0, count);
  }

  List<_ForegroundPaintItem> _projectItemsForCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      camera.center.latitude,
      camera.center.longitude,
      camera.zoom,
      camera.rotation,
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      _featureSignature,
      MapRenderingBudget.decorativeQuality,
    );
    if (_projectedItems != null && _projectedViewKey == viewKey) {
      return _projectedItems!;
    }
    final projected = _projectItems(camera);
    _projectedViewKey = viewKey;
    _projectedItems = List.unmodifiable(projected);
    return _projectedItems!;
  }

  void _rebuildCandidates() {
    final features = widget.features;
    final poiObstacles = [
      for (final poi in features.pois)
        if (poi.type != PoiType.tree) poi.position,
    ];
    final poiObstacleIndex = MapPointAnchorIndex(poiObstacles);
    final mappedTrees = [
      for (final tree in features.pois.where((poi) => poi.type == PoiType.tree))
        if (!_blockedByStructure(tree.position, features) &&
            !poiObstacleIndex.containsNear(tree.position))
          _TreePaintItem(tree.position, _seedForId(tree.id), 1.0),
    ];
    _mappedTrees = _rankedBy(
      mappedTrees,
      rank: (tree) => tree.seed,
      maximum: _mappedTreeCandidateLimit,
    );
    final generated = <_GeneratedTree>[];
    final forestAreas = features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.forest ||
              area.kind == MapFeatureKind.park,
        )
        .toList(growable: false);
    final perArea = forestAreas.isEmpty
        ? 0
        : math.max(8, (_treeCandidateLimit / forestAreas.length).ceil());
    for (var areaIndex = 0; areaIndex < forestAreas.length; areaIndex++) {
      final area = forestAreas[areaIndex];
      if (generated.length >= _treeCandidateLimit || area.ring.length < 3) {
        break;
      }
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
      final localAreas = MapGeometryRules.areasNearArea(area, features.areas);
      final localLines = MapGeometryRules.linesNearArea(area, features.lines);
      final random = math.Random(_areaSeed(area));
      var areaCount = 0;
      for (
        var attempt = 0;
        attempt < perArea * 8 &&
            generated.length < _treeCandidateLimit &&
            areaCount < perArea;
        attempt++
      ) {
        final point = LatLng(
          south + random.nextDouble() * (north - south),
          west + random.nextDouble() * (east - west),
        );
        if (!MapGeometryRules.pointInArea(point, area) ||
            MapGeometryRules.insideAnyWater(point, localAreas) ||
            _blockedByStructureInAreas(point, localAreas) ||
            MapGeometryRules.nearAnyLine(
              point,
              localLines,
              thresholdDegrees: .0003,
            ) ||
            poiObstacleIndex.containsNear(point)) {
          continue;
        }
        final edgeScale = MapGeometryRules.nearPolygonBoundary(point, area.ring)
            ? .72
            : 1.0;
        generated.add(
          _GeneratedTree(point, random.nextInt(1 << 30), edgeScale),
        );
        areaCount++;
      }
    }
    _generatedTrees = _rankedBy(generated, rank: (tree) => tree.seed);

    final rocks = <_GeneratedRock>[];
    var rockAreaIndex = 0;
    for (final area in features.areas.where(
      (area) => area.kind == MapFeatureKind.mountainRock,
    )) {
      if (rocks.length >= 80) break;
      rocks.addAll(
        _sampleRocks(
          area,
          80 - rocks.length,
          rockAreaIndex++,
          poiObstacleIndex,
        ),
      );
    }
    _generatedRocks = _rankedBy(rocks, rank: (rock) => rock.seed);
  }

  List<T> _rankedBy<T>(
    List<T> source, {
    required int Function(T item) rank,
    int? maximum,
  }) {
    final ranked =
        [
          for (final entry in source.indexed)
            (index: entry.$1, item: entry.$2, rank: rank(entry.$2)),
        ]..sort((first, second) {
          final rankOrder = first.rank.compareTo(second.rank);
          return rankOrder != 0
              ? rankOrder
              : first.index.compareTo(second.index);
        });
    final limit = maximum == null
        ? ranked.length
        : math.min(maximum, ranked.length);
    return List.unmodifiable([
      for (final entry in ranked.take(limit)) entry.item,
    ]);
  }

  List<_GeneratedRock> _sampleRocks(
    AreaFeature area,
    int remaining,
    int areaIndex,
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
    final random = math.Random(_areaSeed(area) ^ (areaIndex * 15485863));
    final localAreas = MapGeometryRules.areasNearArea(
      area,
      widget.features.areas,
    );
    final localLines = MapGeometryRules.linesNearArea(
      area,
      widget.features.lines,
    );
    final result = <_GeneratedRock>[];
    for (
      var attempt = 0;
      attempt < remaining * 10 && result.length < remaining;
      attempt++
    ) {
      final point = LatLng(
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      );
      if (!MapGeometryRules.pointInArea(point, area) ||
          MapGeometryRules.insideAnyWater(point, localAreas) ||
          _blockedByStructureInAreas(point, localAreas) ||
          MapGeometryRules.nearAnyLine(
            point,
            localLines,
            thresholdDegrees: .00024,
          ) ||
          poiObstacleIndex.containsNear(point)) {
        continue;
      }
      result.add(_GeneratedRock(point, random.nextInt(1 << 30)));
    }
    return result;
  }

  int _signature(MapFeatureCollection features) => Object.hash(
    Object.hashAll(features.areas.map((area) => area.sourceId ?? area.kind)),
    Object.hashAll(
      features.lines.map((line) => OsmLineProjector.seedFor(line)),
    ),
    Object.hashAll(features.pois.map((poi) => poi.id)),
  );

  int _areaSeed(dynamic area) {
    var seed = area.sourceId?.hashCode ?? area.ring.length;
    for (final point in area.ring) {
      seed = seed * 31 + point.latitude.hashCode;
      seed = seed * 31 + point.longitude.hashCode;
    }
    return seed;
  }

  int _seedForId(String id) {
    var seed = 17;
    for (final unit in id.codeUnits) {
      seed = seed * 31 + unit;
    }
    return seed;
  }

  bool _blockedByStructure(LatLng point, MapFeatureCollection features) {
    return _blockedByStructureInAreas(point, features.areas);
  }

  bool _blockedByStructureInAreas(LatLng point, Iterable<AreaFeature> areas) {
    return MapGeometryRules.insideOrNearAnyAreaKind(
      point,
      areas,
      MapFeatureKind.building,
    );
  }
}

class _ForegroundObjectPainter extends CustomPainter {
  const _ForegroundObjectPainter({
    required this.camera,
    required this.items,
    required this.treeImages,
    required this.rockImage,
    required this.spriteAtlas,
    required this.pivotBoundary,
    required this.slice,
  });

  final MapCamera camera;
  final List<_ForegroundPaintItem> items;
  final List<ui.Image> treeImages;
  final ui.Image? rockImage;
  final ui.Image? spriteAtlas;
  final int? pivotBoundary;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()..filterQuality = FilterQuality.none;
    var start = 0;
    var end = items.length;
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
      _paintAtlasBatch(canvas, size, start, end, atlas, paint);
      return;
    }
    for (var index = start; index < end; index++) {
      final item = items[index];
      switch (item.kind) {
        case _ForegroundKind.rock:
          _paintRock(canvas, size, item.foot, item.seed, paint);
        case _ForegroundKind.tree:
          _paintTree(
            canvas,
            size,
            item.foot,
            item.seed,
            paint,
            scaleMultiplier: item.scaleMultiplier,
          );
      }
    }
  }

  void _paintAtlasBatch(
    Canvas canvas,
    Size canvasSize,
    int start,
    int end,
    ui.Image atlas,
    Paint paint,
  ) {
    final viewport = Offset.zero & canvasSize;
    final transforms = <ui.RSTransform>[];
    final sourceRects = <Rect>[];

    // Rock shadows deliberately remain below the atlas pass.  They are a
    // subtle grounding cue, while actual tree/rock sprites retain their one
    // globally sorted depth order in the following GPU batch.
    for (var index = start; index < end; index++) {
      final item = items[index];
      if (item.kind != _ForegroundKind.rock) continue;
      final scale = _rockScale(item.seed);
      final width = 24 * scale;
      final height = 22 * scale;
      final target = Rect.fromLTWH(
        item.foot.dx - width / 2,
        item.foot.dy - height * .86,
        width,
        height,
      );
      if (!target.inflate(2).overlaps(viewport)) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: item.foot.translate(0, -height * .08),
          width: width * .78,
          height: math.max(2, height * .18),
        ),
        Paint()
          ..color = const Color(0x66243025)
          ..isAntiAlias = false,
      );
    }

    for (var index = start; index < end; index++) {
      final item = items[index];
      switch (item.kind) {
        case _ForegroundKind.tree:
          final scale = _treeScale(item.seed, item.scaleMultiplier);
          final target = Rect.fromLTWH(
            item.foot.dx - 16 * scale,
            item.foot.dy - 46 * scale,
            32 * scale,
            48 * scale,
          );
          if (!target.overlaps(viewport)) continue;
          transforms.add(
            ui.RSTransform.fromComponents(
              rotation: 0,
              scale: scale,
              anchorX: 16,
              anchorY: 46,
              translateX: item.foot.dx,
              translateY: item.foot.dy,
            ),
          );
          sourceRects.add(
            Rect.fromLTWH((item.seed.abs() % 3) * 32.0, 0, 32, 48),
          );
        case _ForegroundKind.rock:
          final scale = _rockScale(item.seed);
          final width = 24 * scale;
          final height = 22 * scale;
          final target = Rect.fromLTWH(
            item.foot.dx - width / 2,
            item.foot.dy - height * .86,
            width,
            height,
          );
          if (!target.inflate(2).overlaps(viewport)) continue;
          transforms.add(
            ui.RSTransform.fromComponents(
              rotation: 0,
              scale: scale,
              anchorX: 12,
              anchorY: 22 * .86,
              translateX: item.foot.dx,
              translateY: item.foot.dy,
            ),
          );
          sourceRects.add(
            Rect.fromLTWH(seedIsOdd(item.seed) ? 120 : 96, 0, 24, 22),
          );
      }
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

  double _treeScale(int seed, double scaleMultiplier) {
    final zoomScale = MapRenderingBudget.decorativeScale(camera.zoom);
    final variantScale = .78 + (seed.abs() % 53) / 100;
    return zoomScale * variantScale * scaleMultiplier;
  }

  double _rockScale(int seed) {
    final zoomScale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .58,
      max: 1,
    );
    final variantScale = .76 + (seed.abs() % 23) / 100;
    return zoomScale * variantScale;
  }

  bool seedIsOdd(int seed) => seed.isOdd;

  void _paintTree(
    Canvas canvas,
    Size canvasSize,
    Offset foot,
    int seed,
    Paint paint, {
    double scaleMultiplier = 1.0,
  }) {
    // Keep a readable silhouette at overview zooms instead of letting the
    // sprite become sub-pixel and appear to disappear.
    final scale = _treeScale(seed, scaleMultiplier);
    final target = Rect.fromLTWH(
      foot.dx - 16 * scale,
      foot.dy - 46 * scale,
      32 * scale,
      48 * scale,
    );
    if (!target.overlaps(Offset.zero & canvasSize)) return;
    if (treeImages.isEmpty) {
      final trunk = Paint()..color = const Color(0xFF5B3D2A);
      final crown = Paint()..color = const Color(0xFF3D722F);
      canvas.drawRect(
        Rect.fromCenter(
          center: foot.translate(0, -8 * scale),
          width: 3 * scale,
          height: 16 * scale,
        ),
        trunk,
      );
      canvas.drawCircle(foot.translate(0, -25 * scale), 12 * scale, crown);
      return;
    }
    final image = treeImages[seed.abs() % treeImages.length];
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      target,
      paint,
    );
  }

  void _paintRock(
    Canvas canvas,
    Size canvasSize,
    Offset foot,
    int seed,
    Paint imagePaint,
  ) {
    final scale = _rockScale(seed);
    final width = 24 * scale;
    final height = 22 * scale;
    final target = Rect.fromLTWH(
      foot.dx - width / 2,
      foot.dy - height * .86,
      width,
      height,
    );
    if (!target.inflate(2).overlaps(Offset.zero & canvasSize)) return;

    canvas.drawOval(
      Rect.fromCenter(
        center: foot.translate(0, -height * .08),
        width: width * .78,
        height: math.max(2, height * .18),
      ),
      Paint()
        ..color = const Color(0x66243025)
        ..isAntiAlias = false,
    );
    final image = rockImage;
    if (image == null) {
      final rock = ui.Path()
        ..moveTo(target.left + width * .08, target.bottom)
        ..lineTo(target.left + width * .20, target.top + height * .34)
        ..lineTo(target.left + width * .48, target.top + height * .08)
        ..lineTo(target.right - width * .12, target.top + height * .42)
        ..lineTo(target.right, target.bottom)
        ..close();
      canvas.drawPath(rock, Paint()..color = const Color(0xFF817B66));
      canvas.drawPath(
        ui.Path()
          ..moveTo(target.left + width * .2, target.top + height * .34)
          ..lineTo(target.left + width * .48, target.top + height * .08)
          ..lineTo(target.left + width * .55, target.bottom)
          ..close(),
        Paint()..color = const Color(0xFFA9A183),
      );
      return;
    }
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    if (seed.isOdd) {
      canvas.save();
      canvas.translate(target.center.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-target.center.dx, 0);
      canvas.drawImageRect(image, source, target, imagePaint);
      canvas.restore();
    } else {
      canvas.drawImageRect(image, source, target, imagePaint);
    }
  }

  @override
  bool shouldRepaint(_ForegroundObjectPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.items != items ||
      oldDelegate.treeImages != treeImages ||
      oldDelegate.rockImage != rockImage ||
      oldDelegate.spriteAtlas != spriteAtlas ||
      oldDelegate.pivotBoundary != pivotBoundary ||
      oldDelegate.slice != slice;
}

class _TreeSpriteBundle {
  const _TreeSpriteBundle({
    required this.trees,
    required this.rock,
    required this.atlas,
  });

  final List<ui.Image> trees;
  final ui.Image rock;
  final ui.Image atlas;
}

class _GeneratedTree {
  const _GeneratedTree(this.position, this.seed, this.scaleMultiplier);

  final LatLng position;
  final int seed;
  final double scaleMultiplier;
}

class _TreePaintItem {
  const _TreePaintItem(this.position, this.seed, this.scaleMultiplier);

  final LatLng position;
  final int seed;
  final double scaleMultiplier;
}

class _GeneratedRock {
  const _GeneratedRock(this.position, this.seed);

  final LatLng position;
  final int seed;
}

enum _ForegroundKind { rock, tree }

class _ForegroundPaintItem {
  const _ForegroundPaintItem._(
    this.kind,
    this.position,
    this.seed,
    this.scaleMultiplier,
    this.foot,
  );

  factory _ForegroundPaintItem.rock(LatLng position, int seed, Offset foot) =>
      _ForegroundPaintItem._(_ForegroundKind.rock, position, seed, 1, foot);

  factory _ForegroundPaintItem.tree(
    LatLng position,
    int seed,
    double scaleMultiplier,
    Offset foot,
  ) => _ForegroundPaintItem._(
    _ForegroundKind.tree,
    position,
    seed,
    scaleMultiplier,
    foot,
  );

  final _ForegroundKind kind;
  final LatLng position;
  final int seed;
  final double scaleMultiplier;
  final Offset foot;
}
