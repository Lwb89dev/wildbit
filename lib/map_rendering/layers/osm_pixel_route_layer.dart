import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/trail_classification.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/osm_line_projector.dart';
import '../composition/pan_projection_frame.dart';
import '../composition/route_visual_style.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel-art paths and forest roads in one Canvas pass.
///
/// Texture assets are repeated through image shaders; no widget is allocated
/// for an individual OSM line segment while the user pans the map.
class OsmPixelRouteLayer extends StatefulWidget {
  const OsmPixelRouteLayer({
    super.key,
    required this.features,
    this.projectionCache,
  });

  final MapFeatureCollection features;
  final ProjectedLineCache? projectionCache;

  @override
  State<OsmPixelRouteLayer> createState() => _OsmPixelRouteLayerState();
}

class _OsmPixelRouteLayerState extends State<OsmPixelRouteLayer> {
  static const _assets = [
    'assets/map/mock/terrain/trail_base_1.png',
    'assets/map/mock/terrain/trail_base_2.png',
    'assets/map/mock/terrain/track_base_1.png',
    'assets/map/mock/terrain/track_base_2.png',
    'assets/map/mock/terrain/rock_base.png',
    'assets/map/mock/terrain/sand_base.png',
    'assets/map/mock/terrain/ford_stones.png',
  ];

  List<ui.Shader> _shaders = const [];
  Future<void>? _loading;
  late final _localProjectionCache = ProjectedLineCache();
  MapFeatureCollection? _orderedSource;
  List<LineFeature> _orderedLines = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant OsmPixelRouteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureImages();
  }

  void _ensureImages() {
    // Runs on every camera rebuild: check the cheap state before scanning.
    if (_shaders.isNotEmpty || _loading != null) return;
    if (!widget.features.lines.any(
      (line) =>
          line.kind == MapFeatureKind.trail || line.kind == MapFeatureKind.road,
    )) {
      return;
    }
    _loading = _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final images = await Future.wait(_assets.map(_resolveImage));
      if (mounted) {
        final shaders = [
          for (final image in images)
            ui.ImageShader(
              image,
              ui.TileMode.repeated,
              ui.TileMode.repeated,
              _RoutePainter._shaderMatrix,
              filterQuality: ui.FilterQuality.none,
            ),
        ];
        setState(() {
          _shaders = shaders;
        });
      }
    } catch (_) {
      // Ground texture unavailable: omit this optional visual layer.
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _resolveImage(String asset) =>
      MapVisualAssetWarmup.resolveImage(context, asset);

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final projectionCache = widget.projectionCache ?? _localProjectionCache;
    projectionCache.beginCamera(camera);
    final lines = _linesForSource();
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RoutePainter(
            camera: camera,
            lines: lines,
            shaders: _shaders,
            projectionCache: projectionCache,
            interacting: MapRenderingBudget.mapInteracting,
          ),
        ),
      ),
    );
  }

  List<LineFeature> _linesForSource() {
    if (identical(_orderedSource, widget.features)) return _orderedLines;
    _orderedSource = widget.features;
    // OSM ordering is not stable, but road/trail draw order is. Sorting once
    // per retained OSM snapshot removes an O(n log n) allocation/sort from
    // every camera frame while preserving the exact same overlap rule.
    final lines =
        widget.features.lines
            .where(
              (line) =>
                  line.kind == MapFeatureKind.trail ||
                  line.kind == MapFeatureKind.road,
            )
            .toList(growable: false)
          ..sort((a, b) {
            // Broad roads form the base; narrow trails remain readable on top at
            // intersections and shared nodes.
            final aOrder = a.kind == MapFeatureKind.road ? 0 : 1;
            final bOrder = b.kind == MapFeatureKind.road ? 0 : 1;
            final layerOrder = aOrder.compareTo(bOrder);
            if (layerOrder != 0) return layerOrder;
            return OsmLineProjector.seedFor(
              a,
            ).compareTo(OsmLineProjector.seedFor(b));
          });
    _orderedLines = List.unmodifiable(lines);
    return _orderedLines;
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.camera,
    required this.lines,
    required this.shaders,
    required this.projectionCache,
    required this.interacting,
  });

  final MapCamera camera;
  final List<LineFeature> lines;
  final List<ui.Shader> shaders;
  final ProjectedLineCache projectionCache;

  /// Gesture state at build time. Texture and vertex budgets depend on it,
  /// so the end of a gesture must repaint even with an unchanged camera.
  final bool interacting;

  final Paint _stroke = Paint()
    ..filterQuality = FilterQuality.none
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.square
    ..strokeJoin = StrokeJoin.bevel;
  final Paint _overlay = Paint()
    ..strokeCap = StrokeCap.square
    ..isAntiAlias = false;
  final Paint _segment = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Projections are cached in a pan frame: one translation places every
    // way, so a drag reprojects only ways that newly enter the viewport.
    final offset = projectionCache.beginCamera(camera);
    final viewport = PanProjectionFrame.viewportIn(size, offset);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final line in lines) {
      if (!MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds)) {
        continue;
      }
      final projected = projectionCache.project(
        line,
        camera,
        // At small scales preserve every line but collapse its geometry more
        // aggressively. The route itself must never disappear just because
        // more neighbouring ways entered the viewport.
        minimumDistancePixels: MapRenderingBudget.routePointDistancePixels(
          line,
          camera.zoom,
        ),
        maximumPoints: MapRenderingBudget.routeMaximumPoints(line, camera.zoom),
      );
      if (!projected.overlaps(viewport)) continue;
      final points = projected.points;
      final seed = OsmLineProjector.seedFor(line);
      final style = RouteVisualStyle.forLine(line, camera.zoom);
      _paintContinuousLine(
        canvas,
        projected,
        color: style.outlineColor,
        width: style.outlineWidth,
      );
      // Textured segments are an aesthetic detail. During a gesture, and at
      // overview zoom where a route can contain hundreds of tiny segments,
      // use the continuous pixel stroke instead. The complete OSM geometry,
      // width, outlines and safety overlays are still painted.
      final useTexture =
          shaders.length >= _assetsCount &&
          style.family != RouteTextureFamily.paved &&
          camera.zoom >= 14.5 &&
          !interacting;
      if (!useTexture) {
        _paintContinuousLine(
          canvas,
          projected,
          width: style.width,
          color: style.fallbackColor,
        );
        _paintTechnicalOverlay(canvas, projected, line.kind, style);
        continue;
      }
      // A long surveyed way can still retain dozens of visible bends after
      // screen-space simplification. Painting each segment with its own
      // save/rotate/draw/restore sequence multiplies Canvas work without
      // adding route evidence. For that case stroke the exact same polyline
      // once with a stable material variant. Short local ways retain their
      // direction-aligned texture treatment.
      if (points.length > _batchedTexturePointThreshold) {
        _paintTexturedLine(
          canvas,
          projected,
          width: style.width,
          shader: shaders[_imageIndex(style.family, seed, 0)],
        );
      } else {
        for (var index = 0; index + 1 < points.length; index++) {
          final delta = points[index + 1] - points[index];
          final length = delta.distance;
          if (length < 1) continue;
          final imageIndex = _imageIndex(style.family, seed, index);
          _paintSegment(
            canvas,
            start: points[index],
            end: points[index + 1],
            width: style.width,
            shader: shaders[imageIndex],
          );
        }
      }
      _paintTechnicalOverlay(canvas, projected, line.kind, style);
    }
    canvas.restore();
  }

  void _paintTechnicalOverlay(
    Canvas canvas,
    ProjectedLine projected,
    MapFeatureKind kind,
    RouteVisualStyle style,
  ) {
    if (projected.points.length < 2) return;
    if (style.isTunnel) {
      _paintDashedLine(
        canvas,
        projected,
        color: const Color(0xFF303A3A),
        width: math.max(1.5, style.width * .26),
        dash: 5,
        gap: 5,
      );
    }
    if (style.isConditional) {
      _paintDashedLine(
        canvas,
        projected,
        color: const Color(0xFFE4A43B),
        width: math.max(1.4, style.width * .22),
        dash: 2,
        gap: 5,
      );
    }
    if (kind != MapFeatureKind.trail) return;
    final difficultyColor = style.difficultyColor;
    if (difficultyColor != null && camera.zoom >= 13) {
      _paintDashedLine(
        canvas,
        projected,
        color: difficultyColor,
        width: math.max(1.4, style.width * .24),
        dash: style.difficulty.level >= 4 ? 5 : 3,
        gap: style.difficulty.level >= 4 ? 8 : 12,
      );
    }
    if (style.visibility == TrailVisibilityStatus.reduced ||
        style.visibility == TrailVisibilityStatus.poor) {
      _paintDashedLine(
        canvas,
        projected,
        color: style.visibility == TrailVisibilityStatus.poor
            ? const Color(0xFFE9D9A2)
            : const Color(0xFFEEE2B8),
        width: math.max(1.2, style.width * .18),
        dash: 2,
        gap: style.visibility == TrailVisibilityStatus.poor ? 7 : 11,
      );
    }
    if (style.access == TrailAccessStatus.restricted) {
      _paintDashedLine(
        canvas,
        projected,
        color: const Color(0xFFD53A35),
        width: math.max(2.0, style.width * .38),
        dash: 7,
        gap: 4,
      );
    }
  }

  /// All dashes of one overlay go to the GPU in a single call; the segment
  /// endpoints are cached with the projected way for later pan frames.
  void _paintDashedLine(
    Canvas canvas,
    ProjectedLine projected, {
    required Color color,
    required double width,
    required double dash,
    required double gap,
  }) {
    final segments = projected.dashes(dash, gap);
    if (segments.isEmpty) return;
    _overlay
      ..color = color
      ..strokeWidth = width;
    canvas.drawRawPoints(ui.PointMode.lines, segments, _overlay);
  }

  static const _assetsCount = 7;
  static const _batchedTexturePointThreshold = 48;

  void _paintContinuousLine(
    Canvas canvas,
    ProjectedLine projected, {
    required double width,
    required Color color,
  }) {
    if (projected.points.length < 2) return;
    _stroke
      ..shader = null
      ..color = color
      ..strokeWidth = width;
    canvas.drawPath(projected.path, _stroke);
  }

  void _paintTexturedLine(
    Canvas canvas,
    ProjectedLine projected, {
    required double width,
    required ui.Shader shader,
  }) {
    if (projected.points.length < 2) return;
    _stroke
      ..shader = shader
      ..strokeWidth = width;
    canvas.drawPath(projected.path, _stroke);
  }

  int _imageIndex(RouteTextureFamily family, int seed, int segment) {
    final variant = (seed + segment).abs() % 2;
    return switch (family) {
      RouteTextureFamily.trail => variant,
      RouteTextureFamily.track => 2 + variant,
      RouteTextureFamily.rock => 4,
      RouteTextureFamily.sand => 5,
      RouteTextureFamily.ford => 6,
      RouteTextureFamily.paved => 0,
    };
  }

  void _paintSegment(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required double width,
    required ui.Shader shader,
  }) {
    final delta = end - start;
    final length = delta.distance;
    final center = Offset.lerp(start, end, .5)!;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.atan2(delta.dy, delta.dx));
    canvas.drawRect(
      Rect.fromLTWH(-length / 2 - width / 2, -width / 2, length + width, width),
      _segment..shader = shader,
    );
    canvas.restore();
  }

  static final Float64List _shaderMatrix = Float64List.fromList(const [
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.lines != lines ||
      oldDelegate.shaders != shaders ||
      oldDelegate.interacting != interacting;
}
