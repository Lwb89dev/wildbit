import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/osm_line_projector.dart';
import '../composition/waterway_network_composer.dart';
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

  ui.Image? _image;
  ui.Shader? _textureShader;
  ui.Image? _mudImage;
  Future<void>? _loading;
  Future<void>? _mudLoading;
  int? _waterwaySourceSignature;
  List<WaterwayRenderStroke>? _composedWaterways;
  int? _projectedViewKey;
  List<_ProjectedWaterwayStroke>? _projectedWaterways;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant OsmPixelWaterwayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The source collection is immutable in practice, but its identity can
    // change when a retained OSM cell is merged. Invalidate only the geometry
    // snapshots, not the already loaded artwork.
    if (_waterwaySignature(widget.features) != _waterwaySourceSignature) {
      _waterwaySourceSignature = null;
      _composedWaterways = null;
      _projectedViewKey = null;
      _projectedWaterways = null;
    }
    _ensureImages();
  }

  void _ensureImages() {
    if (!widget.features.lines.any(
      (line) => line.kind == MapFeatureKind.waterway,
    )) {
      return;
    }
    if (_image == null) _loading ??= _loadImage();
    if (_mudImage == null) _mudLoading ??= _loadMudImage();
  }

  Future<void> _loadMudImage() async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, _mudAsset);
      if (mounted) setState(() => _mudImage = image);
    } catch (_) {
      // The mud-colour stroke below remains as a safe fallback.
    } finally {
      _mudLoading = null;
    }
  }

  Future<void> _loadImage() async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, _asset);
      if (mounted) {
        setState(() {
          _image = image;
          _textureShader = _shaderFor(image);
        });
      }
    } catch (_) {
      // The solid fallback below keeps waterways visible without the asset.
    } finally {
      _loading = null;
    }
  }

  ui.Shader _shaderFor(ui.Image image) => ui.ImageShader(
    image,
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

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // Network composition is topology work, not paint work. Cache it by the
    // source geometry so parent rebuilds (Bit movement, layer toggles, debug
    // sheets) do not re-walk every OSM endpoint. Camera projection remains a
    // separate cache because only that part changes while panning.
    final waterways = _composedForSource();
    final projectedWaterways = _projectedForCamera(camera, waterways);
    // Do not keep the shared ambient clock alive solely for an empty Canvas:
    // many inland viewports contain no linear waterway at all.
    if (projectedWaterways.isEmpty) return const SizedBox.expand();
    final showAmbientDetails =
        MapRenderingBudget.ambientDetailEnabled &&
        !MapRenderingBudget.mapInteracting;
    final animateFlow =
        showAmbientDetails && _image != null && _textureShader != null;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Banks, the water underlay and mud tiles are geographic context.
          // Keep them in their own boundary so ambient flow frames never
          // redraw the expensive static geometry.
          RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaterwayBasePainter(
                camera: camera,
                waterways: projectedWaterways,
                mudImage: _mudImage,
                showMudBanks: MapRenderingBudget.ambientDetailEnabled,
              ),
            ),
          ),
          if (animateFlow)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: MapRenderingBudget.ambientClock,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _WaterwayFlowPainter(
                    camera: camera,
                    waterways: projectedWaterways,
                    image: _image!,
                    texture: _textureShader!,
                    phase: MapRenderingBudget.ambientClock.phase,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<WaterwayRenderStroke> _composedForSource() {
    final source = widget.features.lines.where(
      (line) => line.kind == MapFeatureKind.waterway,
    );
    final signature = _waterwaySignature(widget.features);
    if (_composedWaterways != null && _waterwaySourceSignature == signature) {
      return _composedWaterways!;
    }
    final composed = WaterwayNetworkComposer.compose(source);
    _waterwaySourceSignature = signature;
    _composedWaterways = List.unmodifiable(composed);
    _projectedViewKey = null;
    _projectedWaterways = null;
    return _composedWaterways!;
  }

  List<_ProjectedWaterwayStroke> _projectedForCamera(
    MapCamera camera,
    List<WaterwayRenderStroke> waterways,
  ) {
    final bounds = camera.visibleBounds;
    final viewKey = Object.hash(
      _waterwaySourceSignature,
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
    if (_projectedWaterways != null && _projectedViewKey == viewKey) {
      return _projectedWaterways!;
    }
    final projected = <_ProjectedWaterwayStroke>[];
    for (final waterway in waterways) {
      if (!MapRenderingBudget.pointsMayBeVisible(waterway.points, bounds)) {
        continue;
      }
      final points = OsmLineProjector.projectSimplifiedPoints(
        waterway.points,
        camera.latLngToScreenOffset,
        minimumDistancePixels: MapRenderingBudget.minLinePointDistancePixels,
        maximumPoints: MapRenderingBudget.waterwayMaximumPoints(camera.zoom),
      );
      if (points.length >= 2) {
        projected.add(_ProjectedWaterwayStroke(points));
      }
    }
    _projectedViewKey = viewKey;
    _projectedWaterways = List.unmodifiable(projected);
    return _projectedWaterways!;
  }

  int _waterwaySignature(MapFeatureCollection features) => Object.hashAll(
    features.lines
        .where((line) => line.kind == MapFeatureKind.waterway)
        .map(
          (line) => Object.hash(
            OsmLineProjector.seedFor(line),
            Object.hashAll(line.nodeIds),
            line.metadata.waterwayTag,
            line.metadata.flowDirection,
          ),
        ),
  );
}

class _WaterwayBasePainter extends CustomPainter {
  const _WaterwayBasePainter({
    required this.camera,
    required this.waterways,
    required this.mudImage,
    required this.showMudBanks,
  });

  final MapCamera camera;
  final List<_ProjectedWaterwayStroke> waterways;
  final ui.Image? mudImage;
  final bool showMudBanks;

  @override
  void paint(Canvas canvas, Size size) {
    final width = 12 * math.pow(2, camera.zoom - 16).clamp(.6, 1.25).toDouble();
    for (final waterway in waterways) {
      final points = waterway.points;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF5A412E)
          ..style = PaintingStyle.stroke
          // The bank is a continuous geometric underlay.  The old +4px
          // stroke left transparent pixels in the mud sprite able to reveal
          // the meadow between the bank and the water on short/curved ways.
          ..strokeWidth = width + 10
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF8A6542)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 6
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..isAntiAlias = false,
      );
      // Keep a complete water body underneath the animated texture so gaps
      // between simplified segments never expose terrain below the river.
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
      // Seal the water-facing edge after the earth underlay and before the
      // decorative bank tiles.  This is intentionally only two pixels wider
      // than the water: it prevents alpha holes in a tile from exposing
      // meadow without turning the whole river into a thick brown outline.
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF725238)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 2
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..isAntiAlias = false,
      );
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
      if (showMudBanks && mudImage != null) {
        _paintMudBanks(canvas, points, width, mudImage!);
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
      // Sample along the segment rather than once at its midpoint.  This
      // keeps the bank visually continuous when Overpass returns long ways
      // or very short geometry fragments at a confluence.
      const spacing = 13.0;
      for (final side in const [-1.0, 1.0]) {
        final sideOffset = normal * side * (width / 2 + 4);
        // The source tile is authored horizontally (land on one side and
        // water on the other).  Every tile on a bank follows the river
        // tangent; only the opposite bank is mirrored by a half-turn.
        final angle =
            math.atan2(tangent.dy, tangent.dx) + (side < 0 ? math.pi : 0);
        for (var distance = 0.0; distance <= length; distance += spacing) {
          final tileCenter = start + tangent * distance + sideOffset;
          canvas.save();
          canvas.translate(tileCenter.dx, tileCenter.dy);
          canvas.rotate(angle);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Rect.fromCenter(center: Offset.zero, width: 16, height: 16),
            Paint()..filterQuality = ui.FilterQuality.none,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_WaterwayBasePainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.waterways != waterways ||
      oldDelegate.mudImage != mudImage ||
      oldDelegate.showMudBanks != showMudBanks;
}

class _WaterwayFlowPainter extends CustomPainter {
  const _WaterwayFlowPainter({
    required this.camera,
    required this.waterways,
    required this.image,
    required this.texture,
    required this.phase,
  });

  final MapCamera camera;
  final List<_ProjectedWaterwayStroke> waterways;
  final ui.Image image;
  final ui.Shader texture;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final width = 12 * math.pow(2, camera.zoom - 16).clamp(.6, 1.25).toDouble();
    for (final waterway in waterways) {
      final points = waterway.points;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final coverage = math.max(image.width * 3.0, width * 2.0);
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
        canvas.translate(-phase * image.width.toDouble(), 0);
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

  @override
  bool shouldRepaint(_WaterwayFlowPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.waterways != waterways ||
      oldDelegate.image != image ||
      oldDelegate.texture != texture ||
      oldDelegate.phase != phase;
}

class _ProjectedWaterwayStroke {
  const _ProjectedWaterwayStroke(this.points);

  final List<Offset> points;
}
