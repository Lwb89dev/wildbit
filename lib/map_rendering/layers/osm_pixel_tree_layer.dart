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
  static const _treeCandidateLimit = 600;
  static const _treePaintLimit = 360;
  static const _treeAssets = [
    'assets/map/mock/objects/tree_deciduous_s.png',
    'assets/map/mock/objects/tree_conifer.png',
    'assets/map/mock/objects/tree_deciduous_l.png',
  ];
  static const _rockAsset = 'assets/map/mock/structures/boulder.png';

  List<ui.Image> _treeImages = const [];
  ui.Image? _rockImage;
  List<_TreePaintItem> _mappedTrees = const [];
  List<_GeneratedTree> _generatedTrees = const [];
  List<_GeneratedRock> _generatedRocks = const [];
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
    _rebuildCandidates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_treeImages.isEmpty || _rockImage == null) {
      _loading ??= _loadImages();
    }
  }

  Future<void> _loadImages() async {
    try {
      final images = await Future.wait([
        ..._treeAssets.map(_resolveImage),
        _resolveImage(_rockAsset),
      ]);
      if (mounted) {
        setState(() {
          _treeImages = images.take(_treeAssets.length).toList(growable: false);
          _rockImage = images.last;
        });
      }
    } catch (_) {
      // Optional artwork must not make the map unavailable.
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _resolveImage(String asset) {
    final completer = Completer<ui.Image>();
    final stream = AssetImage(
      asset,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        stream.removeListener(listener);
        completer.complete(image.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
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
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: middleChild == null
            ? _paintSlice(camera, null, ProjectedDepthSlice.all)
            : pivot == null
            // Bit must be mounted before it can publish its first interpolated
            // ground anchor. Until then, keep all objects behind him.
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _paintSlice(camera, null, ProjectedDepthSlice.all),
                  middleChild,
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _paintSlice(camera, pivot, ProjectedDepthSlice.behindPivot),
                  middleChild,
                  _paintSlice(
                    camera,
                    pivot,
                    ProjectedDepthSlice.inFrontOfPivot,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _paintSlice(
    MapCamera camera,
    LatLng? pivot,
    ProjectedDepthSlice slice,
  ) => RepaintBoundary(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _ForegroundObjectPainter(
          camera: camera,
          mappedTrees: _mappedTrees,
          generatedTrees: _generatedTrees,
          generatedRocks: _generatedRocks,
          treeImages: _treeImages,
          rockImage: _rockImage,
          pivot: pivot,
          slice: slice,
        ),
      ),
    ),
  );

  void _rebuildCandidates() {
    final features = widget.features;
    _mappedTrees = [
      for (final tree in features.pois.where((poi) => poi.type == PoiType.tree))
        if (!_blockedByStructure(tree.position, features))
          _TreePaintItem(tree.position, _seedForId(tree.id), 1.0),
    ];
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
        : math.max(24, (_treeCandidateLimit / forestAreas.length).ceil());
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
      final random = math.Random(_areaSeed(area));
      var areaCount = 0;
      for (
        var attempt = 0;
        attempt < perArea * 12 &&
            generated.length < _treeCandidateLimit &&
            areaCount < perArea;
        attempt++
      ) {
        final point = LatLng(
          south + random.nextDouble() * (north - south),
          west + random.nextDouble() * (east - west),
        );
        if (!MapGeometryRules.pointInArea(point, area) ||
            MapGeometryRules.insideAnyWater(point, features.areas) ||
            _blockedByStructure(point, features) ||
            MapGeometryRules.nearAnyLine(
              point,
              features.lines,
              thresholdDegrees: .0003,
            )) {
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
    _generatedTrees = generated;

    final rocks = <_GeneratedRock>[];
    var rockAreaIndex = 0;
    for (final area in features.areas.where(
      (area) => area.kind == MapFeatureKind.mountainRock,
    )) {
      if (rocks.length >= 120) break;
      rocks.addAll(_sampleRocks(area, 120 - rocks.length, rockAreaIndex++));
    }
    _generatedRocks = rocks;
  }

  List<_GeneratedRock> _sampleRocks(
    AreaFeature area,
    int remaining,
    int areaIndex,
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
          MapGeometryRules.insideAnyWater(point, widget.features.areas) ||
          _blockedByStructure(point, widget.features) ||
          MapGeometryRules.nearAnyLine(
            point,
            widget.features.lines,
            thresholdDegrees: .00024,
          )) {
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
    return MapGeometryRules.insideAnyAreaKind(
          point,
          features.areas,
          MapFeatureKind.building,
        ) ||
        MapGeometryRules.nearAnyAreaBoundary(
          point,
          features.areas,
          MapFeatureKind.building,
        );
  }
}

class _ForegroundObjectPainter extends CustomPainter {
  const _ForegroundObjectPainter({
    required this.camera,
    required this.mappedTrees,
    required this.generatedTrees,
    required this.generatedRocks,
    required this.treeImages,
    required this.rockImage,
    required this.pivot,
    required this.slice,
  });

  final MapCamera camera;
  final List<_TreePaintItem> mappedTrees;
  final List<_GeneratedTree> generatedTrees;
  final List<_GeneratedRock> generatedRocks;
  final List<ui.Image> treeImages;
  final ui.Image? rockImage;
  final LatLng? pivot;
  final ProjectedDepthSlice slice;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()..filterQuality = FilterQuality.none;
    // Do not pre-filter by geographic point. The sprite may still overlap the
    // viewport while its anchor is just outside it; target-rect clipping below
    // is stable and removes the edge pop visible during zoom.
    final generatedTreeSubset = MapRenderingBudget.stableDecorativeSubset(
      generatedTrees,
      count: MapRenderingBudget.decorativeLodCount(
        camera.zoom,
        overview: 120,
        close: math.min(
          generatedTrees.length,
          _OsmPixelTreeLayerState._treePaintLimit,
        ),
      ),
      rank: (tree) => tree.seed,
    );
    final generatedRockSubset = MapRenderingBudget.stableDecorativeSubset(
      generatedRocks,
      count: MapRenderingBudget.decorativeCount(
        camera.zoom,
        overview: 40,
        close: generatedRocks.length,
      ),
      rank: (rock) => rock.seed,
    );
    final items = <_ForegroundPaintItem>[
      for (final tree in mappedTrees)
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
      final depth = a.foot.dy.compareTo(b.foot.dy);
      if (depth != 0) return depth;
      // At the same ground depth, low props go first and tall silhouettes
      // may naturally cover their upper edge.
      final kind = a.kind.index.compareTo(b.kind.index);
      if (kind != 0) return kind;
      return a.seed.compareTo(b.seed);
    });
    final pivotFoot = pivot == null
        ? null
        : camera.latLngToScreenOffset(pivot!);
    for (final item in items) {
      if (pivotFoot != null &&
          !ProjectedDepthOrder.belongsToSlice(
            objectFoot: item.foot,
            pivotFoot: pivotFoot,
            slice: slice,
          )) {
        continue;
      }
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
    final zoomScale = MapRenderingBudget.decorativeScale(camera.zoom);
    // Stable per-tree variation creates depth without making sprites jump
    // while panning or changing zoom.
    final variantScale = .78 + (seed.abs() % 53) / 100;
    final scale = zoomScale * variantScale * scaleMultiplier;
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
    final zoomScale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .58,
      max: 1,
    );
    final variantScale = .76 + (seed.abs() % 23) / 100;
    final width = 24 * zoomScale * variantScale;
    final height = 22 * zoomScale * variantScale;
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
      oldDelegate.mappedTrees != mappedTrees ||
      oldDelegate.generatedTrees != generatedTrees ||
      oldDelegate.generatedRocks != generatedRocks ||
      oldDelegate.treeImages != treeImages ||
      oldDelegate.rockImage != rockImage ||
      oldDelegate.pivot != pivot ||
      oldDelegate.slice != slice;
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
