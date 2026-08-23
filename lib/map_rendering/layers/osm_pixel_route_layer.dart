import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../composition/route_visual_style.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel-art paths and forest roads in one Canvas pass.
///
/// Texture assets are repeated through image shaders; no widget is allocated
/// for an individual OSM line segment while the user pans the map.
class OsmPixelRouteLayer extends StatefulWidget {
  const OsmPixelRouteLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelRouteLayer> createState() => _OsmPixelRouteLayerState();
}

class _OsmPixelRouteLayerState extends State<OsmPixelRouteLayer> {
  static const _assets = [
    'assets/map/mock/terrain/trail_base_1.png',
    'assets/map/mock/terrain/trail_base_2.png',
    'assets/map/mock/terrain/track_base_1.png',
    'assets/map/mock/terrain/track_base_2.png',
  ];

  List<ui.Image> _images = const [];
  Future<void>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_images.isEmpty) _loading ??= _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final images = await Future.wait(_assets.map(_resolveImage));
      if (mounted) setState(() => _images = images);
    } catch (_) {
      // Ground texture unavailable: omit this optional visual layer.
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
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RoutePainter(
            camera: MapCamera.of(context),
            features: widget.features,
            images: _images,
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.camera,
    required this.features,
    required this.images,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final List<ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    final shaders = [
      for (final image in images)
        ui.ImageShader(
          image,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          _shaderMatrix,
          filterQuality: ui.FilterQuality.none,
        ),
    ];
    final lines = features.lines.where(
      (line) =>
          (line.kind == MapFeatureKind.trail ||
              line.kind == MapFeatureKind.road) &&
          MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds),
    ).toList(growable: false)
      ..sort((a, b) {
        // Broad roads form the base; narrow trails remain readable on top at
        // intersections and shared nodes.
        final aOrder = a.kind == MapFeatureKind.road ? 0 : 1;
        final bOrder = b.kind == MapFeatureKind.road ? 0 : 1;
        return aOrder.compareTo(bOrder);
      });
    for (final line in lines) {
      final points = OsmLineProjector.projectSimplified(
        line,
        camera.latLngToScreenOffset,
        // At small scales preserve every line but collapse its geometry more
        // aggressively. The route itself must never disappear just because
        // more neighbouring ways entered the viewport.
        minimumDistancePixels: math.max(
          MapRenderingBudget.minLinePointDistancePixels,
          18 - camera.zoom,
        ),
      );
      final seed = OsmLineProjector.seedFor(line);
      final style = RouteVisualStyle.forLine(line, camera.zoom);
      _paintContinuousLine(
        canvas,
        points,
        color: style.outlineColor,
        width: style.outlineWidth,
      );
      if (shaders.length < _assetsCount ||
          style.family == RouteTextureFamily.paved) {
        _paintFallbackLine(
          canvas,
          points,
          width: style.width,
          color: style.fallbackColor,
        );
        continue;
      }
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
  }

  static const _assetsCount = 4;

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

  int _imageIndex(RouteTextureFamily family, int seed, int segment) {
    final variant = (seed + segment).abs() % 2;
    return family == RouteTextureFamily.track ? 2 + variant : variant;
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
      oldDelegate.features != features ||
      oldDelegate.images != images;
}
