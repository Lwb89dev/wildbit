import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/semantics.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/enums/poi_type.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/poi_label_layout.dart';
import '../composition/projected_depth_order.dart';
import '../composition/shelter_sprite_metrics.dart';
import '../performance/map_rendering_budget.dart';

/// Batched POI/structure pass with geographic depth and Canvas semantics.
/// Individual markers no longer allocate widget, tooltip and image subtrees.
class OsmPixelPoiLayer extends StatefulWidget {
  const OsmPixelPoiLayer({
    super.key,
    required this.features,
    this.onPoiTap,
    this.depthPivot,
    this.slice = ProjectedDepthSlice.all,
    this.showLabels = true,
    this.interactive = true,
    this.projectionCache,
  });

  final MapFeatureCollection features;
  final ValueChanged<Poi>? onPoiTap;

  /// Bit's interpolated ground anchor. POIs use the same projected depth
  /// slices as trees and buildings so a refuge behind Bit stays behind him.
  final ValueListenable<LatLng?>? depthPivot;
  final ProjectedDepthSlice slice;

  /// Background depth passes are visual only: labels and hit targets belong
  /// to the foreground pass so there is exactly one accessible POI.
  final bool showLabels;
  final bool interactive;

  /// Share between the two depth slices around Bit. Projection, culling and
  /// sort order are identical; only the final draw range is different.
  final PoiProjectionCache? projectionCache;

  @override
  State<OsmPixelPoiLayer> createState() => _OsmPixelPoiLayerState();
}

class _OsmPixelPoiLayerState extends State<OsmPixelPoiLayer> {
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  final PoiProjectionCache _localProjectionCache = PoiProjectionCache();
  Offset? _pointerDown;
  bool _pointerMoved = false;

  PoiProjectionCache get _projectionCache =>
      widget.projectionCache ?? _localProjectionCache;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant OsmPixelPoiLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _projectionCache.prepare(widget.features);
    _ensureImages();
  }

  void _ensureImages() {
    for (final asset in _requiredAssets()) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Set<String> _requiredAssets() {
    final result = <String>{};
    for (final poi in widget.features.pois) {
      switch (poi.type) {
        case PoiType.shelter:
          result.addAll(const [
            'assets/map/mock/structures/hut_alpine.png',
            'assets/map/mock/structures/hut_bivouac.png',
          ]);
        case PoiType.viewpoint || PoiType.guidepost:
          result.add('assets/map/mock/structures/guidepost_multi.png');
        case PoiType.campsite:
          result.add('assets/map/mock/structures/trail_marker_low.png');
        case PoiType.summit:
          result.add('assets/map/mock/structures/boulder.png');
        case PoiType.parking ||
            PoiType.waterSource ||
            PoiType.tree ||
            PoiType.ford:
          break;
      }
    }
    return result;
  }

  Future<void> _loadImage(String asset) async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, asset);
      if (mounted) setState(() => _images[asset] = image);
    } catch (_) {
      // Procedural glyphs preserve every POI if artwork cannot be loaded.
    } finally {
      _loading.remove(asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    _projectionCache.prepare(widget.features);
    final camera = MapCamera.of(context);
    final pois = widget.features.pois
        .where((poi) => poi.type != PoiType.tree)
        .toList(growable: false);
    final projectedPois = _projectPois(camera, pois);
    Widget paintForPivot(LatLng? pivot) {
      if (pivot == null && widget.slice == ProjectedDepthSlice.inFrontOfPivot) {
        return const SizedBox.expand();
      }
      final pivotBoundary = pivot == null
          ? null
          : ProjectedDepthOrder.firstInFrontIndex(
              projectedPois,
              camera.latLngToScreenOffset(pivot),
              (poi) => poi.foot,
            );
      return CustomPaint(
        size: Size.infinite,
        painter: _PoiPainter(
          camera: camera,
          projectedPois: projectedPois,
          images: Map.unmodifiable(_images),
          onPoiTap: widget.onPoiTap,
          pivotBoundary: pivotBoundary,
          slice: widget.slice,
          showLabels: widget.showLabels,
        ),
      );
    }

    final painted = widget.depthPivot == null
        ? paintForPivot(null)
        : ValueListenableBuilder<LatLng?>(
            valueListenable: widget.depthPivot!,
            builder: (context, pivot, _) => paintForPivot(pivot),
          );
    final scene = RepaintBoundary(child: painted);
    if (!widget.interactive) {
      return IgnorePointer(child: ExcludeSemantics(child: scene));
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDown = event.localPosition;
        _pointerMoved = false;
      },
      onPointerMove: (event) {
        final down = _pointerDown;
        if (down != null && (event.localPosition - down).distance > 8) {
          _pointerMoved = true;
        }
      },
      onPointerCancel: (_) {
        _pointerDown = null;
        _pointerMoved = false;
      },
      onPointerUp: (event) {
        if (!_pointerMoved) {
          final poi = _hitTestPoi(
            camera,
            projectedPois,
            event.localPosition,
            context.size ?? Size.zero,
          );
          if (poi != null) widget.onPoiTap?.call(poi);
        }
        _pointerDown = null;
        _pointerMoved = false;
      },
      child: scene,
    );
  }

  Poi? _hitTestPoi(
    MapCamera camera,
    List<_ProjectedPoi> projectedPois,
    Offset tap,
    Size viewport,
  ) {
    final pivot = widget.depthPivot?.value;
    final boundary = pivot == null
        ? null
        : ProjectedDepthOrder.firstInFrontIndex(
            projectedPois,
            camera.latLngToScreenOffset(pivot),
            (poi) => poi.foot,
          );
    final visibleProjected = _sliceProjectedPois(
      projectedPois,
      boundary: boundary,
      slice: widget.slice,
    );
    final visiblePois = [for (final item in visibleProjected) item.poi];
    for (final label in _composePoiLabels(camera, visiblePois, viewport)) {
      if (label.rect.inflate(3).contains(tap)) return label.poi;
    }
    Poi? closest;
    var closestDistance = double.infinity;
    for (final projected in visibleProjected) {
      final poi = projected.poi;
      final markerSize = MapRenderingBudget.poiMarkerSize(
        poi.type,
        camera.zoom,
      );
      final center = projected.foot.translate(0, -markerSize / 2);
      final distance = (tap - center).distance;
      final hitRadius = math.max(22.0, markerSize * .72);
      if (distance <= hitRadius && distance < closestDistance) {
        closest = poi;
        closestDistance = distance;
      }
    }
    return closest;
  }

  List<_ProjectedPoi> _projectPois(MapCamera camera, List<Poi> pois) {
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
    );
    final cached = _projectionCache._projectedPois;
    if (cached != null && _projectionCache.projectedPoiViewKey == viewKey) {
      return cached;
    }
    final projected = <_ProjectedPoi>[
      for (final poi in pois)
        if (bounds.contains(poi.position))
          (poi: poi, foot: camera.latLngToScreenOffset(poi.position)),
    ];
    final paintLimit = MapRenderingBudget.poiPaintLimit(camera.zoom);
    if (projected.length > paintLimit) {
      final priority = [
        for (final item in projected)
          if (MapRenderingBudget.poiPriority(item.poi.type) <= 1) item,
      ];
      final secondary = [
        for (final item in projected)
          if (MapRenderingBudget.poiPriority(item.poi.type) > 1) item,
      ];
      final remaining = math.max(0, paintLimit - priority.length);
      projected
        ..clear()
        ..addAll(priority)
        ..addAll(
          MapRenderingBudget.stableDecorativeSubset(
            secondary,
            count: remaining,
            rank: (item) => item.poi.id.hashCode,
          ),
        );
    }
    projected.sort((a, b) {
      final depth = ProjectedDepthOrder.compare(
        firstFoot: a.foot,
        secondFoot: b.foot,
      );
      return depth != 0 ? depth : a.poi.id.compareTo(b.poi.id);
    });
    _projectionCache.projectedPoiViewKey = viewKey;
    _projectionCache._projectedPois = List.unmodifiable(projected);
    return _projectionCache._projectedPois!;
  }
}

/// Cache of the cull/project/sort phase shared by POI depth slices.
class PoiProjectionCache {
  MapFeatureCollection? _source;
  int? projectedPoiViewKey;
  List<_ProjectedPoi>? _projectedPois;

  void prepare(MapFeatureCollection source) {
    if (identical(_source, source)) return;
    _source = source;
    projectedPoiViewKey = null;
    _projectedPois = null;
  }

  /// Releases only the current viewport projection, never the POI source.
  void clearTransient() {
    projectedPoiViewKey = null;
    _projectedPois = null;
  }
}

class _PoiPainter extends CustomPainter {
  const _PoiPainter({
    required this.camera,
    required this.projectedPois,
    required this.images,
    required this.onPoiTap,
    required this.pivotBoundary,
    required this.slice,
    required this.showLabels,
  });

  final MapCamera camera;
  final List<_ProjectedPoi> projectedPois;
  final Map<String, ui.Image> images;
  final ValueChanged<Poi>? onPoiTap;
  final int? pivotBoundary;
  final ProjectedDepthSlice slice;
  final bool showLabels;

  List<_ProjectedPoi> get _visibleProjectedPois =>
      _sliceProjectedPois(projectedPois, boundary: pivotBoundary, slice: slice);

  @override
  void paint(Canvas canvas, Size size) {
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    final visibleProjected = _visibleProjectedPois;
    final visiblePois = [for (final item in visibleProjected) item.poi];
    final projectedFeet = {
      for (final item in visibleProjected) item.poi.id: item.foot,
    };
    for (final item in visibleProjected) {
      final poi = item.poi;
      final foot = item.foot;
      final markerSize = MapRenderingBudget.poiMarkerSize(
        poi.type,
        camera.zoom,
      );
      if (foot.dx < -markerSize ||
          foot.dy < -markerSize ||
          foot.dx > size.width + markerSize ||
          foot.dy > size.height + markerSize) {
        continue;
      }
      final asset = _assetFor(poi);
      final image = asset == null ? null : images[asset];
      if (image == null) {
        _paintGlyph(canvas, foot, markerSize, poi.type);
        continue;
      }
      final destination = poi.type == PoiType.shelter
          ? ShelterSpriteMetrics.destination(
              foot: foot,
              markerSize: markerSize,
              imageWidth: image.width,
              imageHeight: image.height,
              shelterType: poi.metadata.shelterType,
            )
          : _squareDestination(foot, markerSize, image);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(destination.center.dx, foot.dy - 1),
          width: destination.width * .72,
          height: math.max(2, destination.height * .13),
        ),
        Paint()..color = const Color(0x55202C21),
      );
      canvas.drawImageRect(
        image,
        poi.type == PoiType.shelter
            ? ShelterSpriteMetrics.sourceRect(
                imageWidth: image.width,
                imageHeight: image.height,
                shelterType: poi.metadata.shelterType,
              )
            : Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
        destination,
        imagePaint,
      );
    }
    // Markers are navigational evidence and never disappear. Label layout is
    // deferred while the camera is moving, then restored on the idle frame.
    if (!showLabels || MapRenderingBudget.mapInteracting) return;
    for (final label in _composePoiLabels(
      camera,
      visiblePois,
      size,
      projectedFeet: projectedFeet,
    )) {
      _paintLabel(canvas, label);
    }
  }

  Rect _squareDestination(Offset foot, double markerSize, ui.Image image) {
    final imageScale = math.min(
      markerSize / image.width,
      markerSize / image.height,
    );
    final width = image.width * imageScale;
    final height = image.height * imageScale;
    return Rect.fromLTWH(foot.dx - width / 2, foot.dy - height, width, height);
  }

  void _paintLabel(Canvas canvas, _PoiLabelVisual label) {
    final rect = label.rect;
    final shadowPaint = Paint()
      ..color = const Color(0x77202C21)
      ..isAntiAlias = false;
    final borderPaint = Paint()
      ..color = const Color(0xFF5B432E)
      ..isAntiAlias = false;
    final fillPaint = Paint()
      ..color = const Color(0xF7FFF4D1)
      ..isAntiAlias = false;
    canvas.drawRect(rect.shift(const Offset(2, 2)), shadowPaint);
    canvas.drawRect(rect, borderPaint);
    canvas.drawRect(rect.deflate(1), fillPaint);
    label.textPainter.paint(canvas, rect.topLeft + const Offset(6, 3));
  }

  String? _assetFor(Poi poi) => switch (poi.type) {
    PoiType.shelter =>
      poi.metadata.shelterType == 'wilderness_hut' ||
              poi.metadata.shelterType == 'shelter'
          ? 'assets/map/mock/structures/hut_bivouac.png'
          : 'assets/map/mock/structures/hut_alpine.png',
    PoiType.viewpoint ||
    PoiType.guidepost => 'assets/map/mock/structures/guidepost_multi.png',
    PoiType.campsite => 'assets/map/mock/structures/trail_marker_low.png',
    PoiType.summit => 'assets/map/mock/structures/boulder.png',
    PoiType.parking ||
    PoiType.waterSource ||
    PoiType.tree ||
    PoiType.ford => null,
  };

  void _paintGlyph(
    Canvas canvas,
    Offset foot,
    double markerSize,
    PoiType type,
  ) {
    final dimension = markerSize * .76;
    final center = foot.translate(0, -dimension / 2);
    canvas.drawCircle(
      center.translate(1.5, 2),
      dimension / 2,
      Paint()..color = const Color(0x55202C21),
    );
    canvas.drawCircle(
      center,
      dimension / 2,
      Paint()..color = const Color(0xFFFFF7DA),
    );
    canvas.drawCircle(
      center,
      dimension / 2,
      Paint()
        ..color = const Color(0xFF684C32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, markerSize * .055)
        ..isAntiAlias = false,
    );
    final pixel = math.max(1.0, markerSize / 13);
    final glyph = Paint()..isAntiAlias = false;
    switch (type) {
      case PoiType.parking:
        glyph.color = const Color(0xFF315E7A);
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - 3 * pixel,
            center.dy - 4 * pixel,
            2 * pixel,
            8 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 4 * pixel,
            4 * pixel,
            2 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 2 * pixel,
            3 * pixel,
            2 * pixel,
          ),
          glyph,
        );
      case PoiType.waterSource:
        glyph.color = const Color(0xFF2E83A6);
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 4 * pixel,
            2 * pixel,
            6 * pixel,
          ),
          glyph,
        );
      case PoiType.ford:
        glyph.color = const Color(0xFF426E7B);
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - 4 * pixel,
            center.dy - pixel,
            3 * pixel,
            2 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx + pixel,
            center.dy + pixel,
            3 * pixel,
            2 * pixel,
          ),
          glyph,
        );
      default:
        glyph.color = const Color(0xFF376342);
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 2 * pixel, height: 8 * pixel),
          glyph,
        );
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 8 * pixel, height: 2 * pixel),
          glyph,
        );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final visibleProjected = _visibleProjectedPois;
    final visiblePois = [for (final item in visibleProjected) item.poi];
    final projectedFeet = {
      for (final item in visibleProjected) item.poi.id: item.foot,
    };
    final labels = {
      for (final label in _composePoiLabels(
        camera,
        visiblePois,
        size,
        projectedFeet: projectedFeet,
      ))
        label.poi.id: label.rect,
    };
    return [
      for (final poi in visiblePois)
        CustomPainterSemantics(
          rect:
              labels[poi.id]?.expandToInclude(
                Rect.fromCenter(
                  center: camera
                      .latLngToScreenOffset(poi.position)
                      .translate(
                        0,
                        -MapRenderingBudget.poiMarkerSize(
                              poi.type,
                              camera.zoom,
                            ) /
                            2,
                      ),
                  width: MapRenderingBudget.poiMarkerSize(
                    poi.type,
                    camera.zoom,
                  ),
                  height: MapRenderingBudget.poiMarkerSize(
                    poi.type,
                    camera.zoom,
                  ),
                ),
              ) ??
              Rect.fromCenter(
                center: camera
                    .latLngToScreenOffset(poi.position)
                    .translate(
                      0,
                      -MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom) /
                          2,
                    ),
                width: MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom),
                height: MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom),
              ),
          properties: SemanticsProperties(
            label: poi.name,
            button: onPoiTap != null,
            onTap: onPoiTap == null ? null : () => onPoiTap!(poi),
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRepaint(_PoiPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.projectedPois != projectedPois ||
      oldDelegate.images != images ||
      oldDelegate.onPoiTap != onPoiTap ||
      oldDelegate.pivotBoundary != pivotBoundary ||
      oldDelegate.slice != slice ||
      oldDelegate.showLabels != showLabels;

  @override
  bool shouldRebuildSemantics(_PoiPainter oldDelegate) =>
      shouldRepaint(oldDelegate);
}

typedef _ProjectedPoi = ({Poi poi, Offset foot});

List<_ProjectedPoi> _sliceProjectedPois(
  List<_ProjectedPoi> projected, {
  required int? boundary,
  required ProjectedDepthSlice slice,
}) {
  if (boundary == null || slice == ProjectedDepthSlice.all) return projected;
  return switch (slice) {
    ProjectedDepthSlice.all => projected,
    ProjectedDepthSlice.behindPivot => projected.sublist(0, boundary),
    ProjectedDepthSlice.inFrontOfPivot => projected.sublist(boundary),
  };
}

const _poiLabelStyle = TextStyle(
  color: Color(0xFF273426),
  fontSize: 11,
  fontWeight: FontWeight.w800,
  height: 1.05,
);

class _PoiLabelVisual {
  const _PoiLabelVisual({
    required this.poi,
    required this.rect,
    required this.textPainter,
  });

  final Poi poi;
  final Rect rect;
  final TextPainter textPainter;
}

List<_PoiLabelVisual> _composePoiLabels(
  MapCamera camera,
  List<Poi> pois,
  Size viewport, {
  Map<String, Offset>? projectedFeet,
}) {
  if (viewport.isEmpty) return const [];
  final visible = <Poi>[];
  final markerRects = <String, Rect>{};
  for (final poi in pois) {
    if (poi.type == PoiType.tree ||
        !camera.visibleBounds.contains(poi.position)) {
      continue;
    }
    final markerSize = MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom);
    final foot =
        projectedFeet?[poi.id] ?? camera.latLngToScreenOffset(poi.position);
    final rect = Rect.fromLTWH(
      foot.dx - markerSize / 2,
      foot.dy - markerSize,
      markerSize,
      markerSize,
    );
    if (!rect.inflate(markerSize).overlaps(Offset.zero & viewport)) continue;
    visible.add(poi);
    markerRects[poi.id] = rect;
  }

  final painters = <String, TextPainter>{};
  final candidates = <PoiLabelCandidate>[];
  for (final poi in visible) {
    if (camera.zoom < MapRenderingBudget.poiLabelMinZoom(poi.type) ||
        poi.name.trim().isEmpty) {
      continue;
    }
    final painter = TextPainter(
      text: TextSpan(text: poi.name.trim(), style: _poiLabelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 124);
    painters[poi.id] = painter;
    candidates.add(
      PoiLabelCandidate(
        id: poi.id,
        markerRect: markerRects[poi.id]!,
        labelSize: Size(painter.width + 12, painter.height + 6),
        priority: MapRenderingBudget.poiPriority(poi.type),
      ),
    );
  }

  final placements = PoiLabelLayout.compose(
    candidates: candidates,
    viewport: viewport,
    reserved: [
      Rect.fromLTWH(0, 0, viewport.width, math.min(58, viewport.height)),
      if (viewport.width > 90 && viewport.height > 190)
        Rect.fromLTWH(viewport.width - 78, viewport.height - 190, 78, 190),
      if (viewport.height > 64)
        Rect.fromLTWH(0, viewport.height - 54, viewport.width, 54),
    ],
  );
  final poiById = {for (final poi in visible) poi.id: poi};
  return [
    for (final placement in placements)
      if (poiById[placement.id] case final poi?)
        _PoiLabelVisual(
          poi: poi,
          rect: placement.rect,
          textPainter: painters[placement.id]!,
        ),
  ];
}
