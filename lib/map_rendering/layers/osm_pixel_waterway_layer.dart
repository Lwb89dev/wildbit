import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../performance/map_rendering_budget.dart';

/// Pixel-art pass for linear OSM waterways (stream, river, canal, ditch).
///
/// This is intentionally separate from water polygons: a mapped stream is a
/// real visual feature, but is never inflated into an invented riverbank.
class OsmPixelWaterwayLayer extends StatefulWidget {
  const OsmPixelWaterwayLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelWaterwayLayer> createState() =>
      _OsmPixelWaterwayLayerState();
}

class _OsmPixelWaterwayLayerState extends State<OsmPixelWaterwayLayer> {
  static const _asset = 'assets/map/mock/terrain/water_flow.png';

  ui.Image? _image;
  Future<void>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_image == null) _loading ??= _loadImage();
  }

  Future<void> _loadImage() async {
    final completer = Completer<ui.Image>();
    final stream = const AssetImage(_asset).resolve(
      createLocalImageConfiguration(context),
    );
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
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _WaterwayPainter(
            camera: MapCamera.of(context),
            features: widget.features,
            image: _image,
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
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final width =
        12 * math.pow(2, camera.zoom - 16).clamp(.6, 1.25).toDouble();
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
              1, 0, 0, 0,
              0, 1, 0, 0,
              0, 0, 1, 0,
              0, 0, 0, 1,
            ]),
            filterQuality: ui.FilterQuality.none,
          );
    for (final waterway in waterways) {
      final points = OsmLineProjector.projectSimplified(
        waterway,
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
          ..color = const Color(0xFF34483A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 6
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF71844A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 3.5
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..isAntiAlias = false,
      );
      if (texture == null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF3987A3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.bevel,
        );
        continue;
      }
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
        canvas.drawRect(
          Rect.fromLTWH(
            -length / 2 - width / 2,
            -width / 2,
            length + width,
            width,
          ),
          Paint()..shader = texture,
        );
        canvas.restore();
      }
      final highlightStrength = ((camera.zoom - 9) / 4.5).clamp(0.0, 1.0);
      if (highlightStrength > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFC3E9E5).withValues(
              alpha: .6 * highlightStrength,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, width * .12)
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.bevel
            ..isAntiAlias = false,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaterwayPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.features != features ||
      oldDelegate.image != image;
}
