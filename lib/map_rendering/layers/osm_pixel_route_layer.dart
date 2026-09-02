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
    if (!widget.features.lines.any(
      (line) =>
          line.kind == MapFeatureKind.trail || line.kind == MapFeatureKind.road,
    )) {
      return;
    }
    if (_shaders.isEmpty) _loading ??= _loadImages();
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
    projectionCache.beginView(_viewKey(camera, widget.features));
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

  String _viewKey(MapCamera camera, MapFeatureCollection features) {
    final bounds = camera.visibleBounds;
    // A projection cache may save work but must never quantise geography.
    // At walking zoom, a rounded centre/rotation can visibly displace a trail
    // from the cursor or hide a small junction until the next cache miss.
    return '${identityHashCode(features)}:${camera.center.latitude}:'
        '${camera.center.longitude}:${camera.zoom}:${camera.rotation}:'
        '${bounds.south}:${bounds.west}:${bounds.north}:${bounds.east}';
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.camera,
    required this.lines,
    required this.shaders,
    required this.projectionCache,
  });

  final MapCamera camera;
  final List<LineFeature> lines;
  final List<ui.Shader> shaders;
  final ProjectedLineCache projectionCache;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      if (!MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds)) {
        continue;
      }
      final points = projectionCache.project(
        line,
        camera.latLngToScreenOffset,
        // At small scales preserve every line but collapse its geometry more
        // aggressively. The route itself must never disappear just because
        // more neighbouring ways entered the viewport.
        minimumDistancePixels: MapRenderingBudget.routePointDistancePixels(
          line,
          camera.zoom,
        ),
        maximumPoints: MapRenderingBudget.routeMaximumPoints(line, camera.zoom),
      );
      if (!OsmLineProjector.overlapsViewport(points, size)) continue;
      final seed = OsmLineProjector.seedFor(line);
      final style = RouteVisualStyle.forLine(line, camera.zoom);
      _paintContinuousLine(
        canvas,
        points,
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
          !MapRenderingBudget.mapInteracting;
      if (!useTexture) {
        _paintFallbackLine(
          canvas,
          points,
          width: style.width,
          color: style.fallbackColor,
        );
        _paintTechnicalOverlay(canvas, points, line.kind, style);
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
          points,
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
      _paintTechnicalOverlay(canvas, points, line.kind, style);
    }
  }

  void _paintTechnicalOverlay(
    Canvas canvas,
    List<Offset> points,
    MapFeatureKind kind,
    RouteVisualStyle style,
  ) {
    if (points.length < 2) return;
    if (style.isTunnel) {
      _paintDashedLine(
        canvas,
        points,
        paint: Paint()
          ..color = const Color(0xFF303A3A)
          ..strokeWidth = math.max(1.5, style.width * .26)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
        dash: 5,
        gap: 5,
      );
    }
    if (style.isConditional) {
      _paintDashedLine(
        canvas,
        points,
        paint: Paint()
          ..color = const Color(0xFFE4A43B)
          ..strokeWidth = math.max(1.4, style.width * .22)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
        dash: 2,
        gap: 5,
      );
    }
    if (kind != MapFeatureKind.trail) return;
    final difficultyColor = style.difficultyColor;
    if (difficultyColor != null && camera.zoom >= 13) {
      _paintDashedLine(
        canvas,
        points,
        paint: Paint()
          ..color = difficultyColor
          ..strokeWidth = math.max(1.4, style.width * .24)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
        dash: style.difficulty.level >= 4 ? 5 : 3,
        gap: style.difficulty.level >= 4 ? 8 : 12,
      );
    }
    if (style.visibility == TrailVisibilityStatus.reduced ||
        style.visibility == TrailVisibilityStatus.poor) {
      _paintDashedLine(
        canvas,
        points,
        paint: Paint()
          ..color = style.visibility == TrailVisibilityStatus.poor
              ? const Color(0xFFE9D9A2)
              : const Color(0xFFEEE2B8)
          ..strokeWidth = math.max(1.2, style.width * .18)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
        dash: 2,
        gap: style.visibility == TrailVisibilityStatus.poor ? 7 : 11,
      );
    }
    if (style.access == TrailAccessStatus.restricted) {
      _paintDashedLine(
        canvas,
        points,
        paint: Paint()
          ..color = const Color(0xFFD53A35)
          ..strokeWidth = math.max(2.0, style.width * .38)
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
        dash: 7,
        gap: 4,
      );
    }
  }

  void _paintDashedLine(
    Canvas canvas,
    List<Offset> points, {
    required Paint paint,
    required double dash,
    required double gap,
  }) {
    var drawing = true;
    var remaining = dash;
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final delta = points[index + 1] - start;
      final length = delta.distance;
      if (length <= 0) continue;
      final direction = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final step = math.min(remaining, length - travelled);
        if (drawing && step > 0) {
          canvas.drawLine(
            start + direction * travelled,
            start + direction * (travelled + step),
            paint,
          );
        }
        travelled += step;
        remaining -= step;
        if (remaining <= .001) {
          drawing = !drawing;
          remaining = drawing ? dash : gap;
        }
      }
    }
  }

  static const _assetsCount = 7;
  static const _batchedTexturePointThreshold = 48;

  void _paintFallbackLine(
    Canvas canvas,
    List<Offset> points, {
    required double width,
    required Color color,
  }) {
    _paintContinuousLine(canvas, points, color: color, width: width);
  }

  void _paintContinuousLine(
    Canvas canvas,
    List<Offset> points, {
    required double width,
    required Color color,
  }) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.bevel
        ..strokeWidth = width,
    );
  }

  void _paintTexturedLine(
    Canvas canvas,
    List<Offset> points, {
    required double width,
    required ui.Shader shader,
  }) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.bevel
        ..strokeWidth = width
        ..filterQuality = FilterQuality.none,
    );
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
      Paint()..shader = shader,
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
      oldDelegate.shaders != shaders;
}
