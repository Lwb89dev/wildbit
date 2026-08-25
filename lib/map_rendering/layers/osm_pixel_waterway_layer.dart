import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../composition/waterway_flow_resolver.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel-art pass for linear OSM waterways (stream, river, canal, ditch).
///
/// This is intentionally separate from water polygons: a mapped stream is a
/// real visual feature, but is never inflated into an invented riverbank.
class OsmPixelWaterwayLayer extends StatefulWidget {
  const OsmPixelWaterwayLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelWaterwayLayer> createState() => _OsmPixelWaterwayLayerState();
}

class _OsmPixelWaterwayLayerState extends State<OsmPixelWaterwayLayer> {
  static const _asset = 'assets/map/mock/terrain/water_flow.png';
  static const _mudAsset = 'assets/map/mock/terrain/shore_mud_bank.png';
  static const _flowStep = Duration(milliseconds: 140);

  ui.Image? _image;
  ui.Image? _mudImage;
  Future<void>? _loading;
  Future<void>? _mudLoading;
  final ValueNotifier<double> _flowPhase = ValueNotifier(0);
  Timer? _flowTimer;

  @override
  void initState() {
    super.initState();
    _flowTimer = Timer.periodic(_flowStep, (_) {
      _flowPhase.value = (_flowPhase.value + 1 / 20) % 1;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_image == null) _loading ??= _loadImage();
    if (_mudImage == null) _mudLoading ??= _loadMudImage();
  }

  Future<void> _loadMudImage() async {
    final completer = Completer<ui.Image>();
    final stream = const AssetImage(
      _mudAsset,
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
    try {
      final image = await completer.future;
      if (mounted) setState(() => _mudImage = image);
    } catch (_) {
      // The mud-colour stroke below remains as a safe fallback.
    } finally {
      _mudLoading = null;
    }
  }

  Future<void> _loadImage() async {
    final completer = Completer<ui.Image>();
    final stream = const AssetImage(
      _asset,
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
    try {
      final image = await completer.future;
      if (mounted) setState(() => _image = image);
    } catch (_) {
      // The solid fallback below keeps waterways visible without the asset.
    } finally {
      _loading = null;
    }
  }

  @override
  void dispose() {
    _flowTimer?.cancel();
    _flowPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _flowPhase,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _WaterwayPainter(
              camera: MapCamera.of(context),
              features: widget.features,
              image: _image,
              mudImage: _mudImage,
              phase: _flowPhase.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterwayPainter extends CustomPainter {
  const _WaterwayPainter({
    required this.camera,
    required this.features,
    required this.image,
    required this.mudImage,
    required this.phase,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final ui.Image? image;
  final ui.Image? mudImage;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final width = 12 * math.pow(2, camera.zoom - 16).clamp(.6, 1.25).toDouble();
    final waterways = features.lines
        .where((line) => line.kind == MapFeatureKind.waterway)
        .where(
          (line) =>
              MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds),
        );
    final texture = image == null
        ? null
        : ui.ImageShader(
            image!,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Float64List.fromList(const [
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
            ]),
            filterQuality: ui.FilterQuality.none,
          );
    for (final waterway in waterways) {
      final sourcePoints = WaterwayFlowResolver.ordered(
        waterway,
        waterway.points,
      );
      final points = OsmLineProjector.projectSimplifiedPoints(
        sourcePoints,
        camera.latLngToScreenOffset,
        minimumDistancePixels: MapRenderingBudget.minLinePointDistancePixels,
      );
      if (points.length < 2) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF5A412E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 4
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF8A6542)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 2
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..isAntiAlias = false,
      );
      // The animated texture is a detail pass. Keep a complete water body
      // underneath it so gaps between simplified segments never expose the
      // terrain below the river.
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF3987A3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..isAntiAlias = false,
      );
      if (mudImage != null) {
        _paintMudBanks(canvas, points, width, mudImage!);
      }
      if (texture == null) {
        continue;
      }
      final coverage = math.max(image!.width * 3.0, width * 2.0);
      for (var index = 0; index + 1 < points.length; index++) {
        final start = points[index];
        final end = points[index + 1];
        final delta = end - start;
        final length = delta.distance;
        if (length < 1) continue;
        final center = Offset.lerp(start, end, .5)!;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.atan2(delta.dy, delta.dx));
        // Local +X is the waterway tangent, so the phase can only travel
        // along the river and never across its width.
        canvas.translate(-phase * image!.width.toDouble(), 0);
        canvas.drawRect(
          Rect.fromLTWH(
            -length / 2 - coverage,
            -width / 2,
            length + coverage * 2,
            width,
          ),
          Paint()..shader = texture,
        );
        canvas.restore();
      }
      // Curved ways are painted one tangent-aligned segment at a time.
      // Textured caps close the tiny bevel gaps at joins without changing the
      // geographic centerline or inventing a wider river.
      final joinPaint = Paint()..shader = texture;
      for (final point in points) {
        canvas.drawCircle(point, width / 2, joinPaint);
      }
      final highlightStrength = ((camera.zoom - 9) / 4.5).clamp(0.0, 1.0);
      if (highlightStrength > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(
              0xFFC3E9E5,
            ).withValues(alpha: .6 * highlightStrength)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, width * .12)
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.bevel
            ..isAntiAlias = false,
        );
      }
    }
  }

  void _paintMudBanks(
    Canvas canvas,
    List<Offset> points,
    double width,
    ui.Image image,
  ) {
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      final delta = end - start;
      final length = delta.distance;
      if (length < 4) continue;
      final tangent = delta / length;
      final normal = Offset(-tangent.dy, tangent.dx);
      final center = Offset.lerp(start, end, .5)!;
      for (final side in const [-1.0, 1.0]) {
        final waterDirection = normal * -side;
        final tileCenter = center + normal * side * (width / 2 + 3);
        canvas.save();
        canvas.translate(tileCenter.dx, tileCenter.dy);
        canvas.rotate(math.atan2(waterDirection.dy, waterDirection.dx));
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromCenter(center: Offset.zero, width: 16, height: 16),
          Paint()..filterQuality = ui.FilterQuality.none,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WaterwayPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.features != features ||
      oldDelegate.image != image ||
      oldDelegate.mudImage != mudImage ||
      oldDelegate.phase != phase;
}
