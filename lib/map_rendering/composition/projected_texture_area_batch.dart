import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/area_feature.dart';
import 'osm_water_polygon_projector.dart';

/// Description of one geographic polygon in a batched texture pass.
class ProjectedTextureAreaSpec {
  const ProjectedTextureAreaSpec({
    required this.area,
    required this.asset,
    required this.fallbackColor,
    this.borderColor,
    this.borderWidth = 0,
  });

  final AreaFeature area;
  final String asset;
  final Color fallbackColor;
  final Color? borderColor;
  final double borderWidth;
}

/// Paints many textured OSM polygons through one render object.
///
/// Textures are anchored to each projected polygon instead of to the screen,
/// preventing the artwork from swimming during pan. One shader is allocated
/// per asset and reused by every polygon in the same frame.
class ProjectedTextureAreaBatch extends StatefulWidget {
  const ProjectedTextureAreaBatch({
    super.key,
    required this.camera,
    required this.areas,
  });

  final MapCamera camera;
  final List<ProjectedTextureAreaSpec> areas;

  @override
  State<ProjectedTextureAreaBatch> createState() =>
      _ProjectedTextureAreaBatchState();
}

class _ProjectedTextureAreaBatchState extends State<ProjectedTextureAreaBatch> {
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant ProjectedTextureAreaBatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureImages();
  }

  void _ensureImages() {
    for (final asset in widget.areas.map((area) => area.asset).toSet()) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Future<void> _loadImage(String asset) async {
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
    try {
      final image = await completer.future;
      if (mounted) setState(() => _images[asset] = image);
    } catch (_) {
      // Every spec supplies a semantically correct solid fallback.
    } finally {
      _loading.remove(asset);
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _TextureAreaBatchPainter(
        camera: widget.camera,
        areas: widget.areas,
        images: Map.unmodifiable(_images),
      ),
    ),
  );
}

class _TextureAreaBatchPainter extends CustomPainter {
  const _TextureAreaBatchPainter({
    required this.camera,
    required this.areas,
    required this.images,
  });

  final MapCamera camera;
  final List<ProjectedTextureAreaSpec> areas;
  final Map<String, ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    final shaders = <String, ui.Shader>{
      for (final entry in images.entries)
        entry.key: ui.ImageShader(
          entry.value,
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
        ),
    };
    for (final spec in areas) {
      final polygon = OsmWaterPolygonProjector.project(
        spec.area,
        camera.latLngToScreenOffset,
      );
      if (polygon.length < 3) continue;
      final path = _pathForArea(spec.area, polygon);
      final bounds = path.getBounds();
      if (bounds.isEmpty || !bounds.overlaps(Offset.zero & size)) continue;
      final shader = shaders[spec.asset];
      if (shader == null) {
        canvas.drawPath(path, Paint()..color = spec.fallbackColor);
      } else {
        canvas.save();
        canvas.clipPath(path);
        // Draw in polygon-local coordinates. The shader therefore follows
        // the feature's projected origin as the camera moves.
        canvas.translate(bounds.left, bounds.top);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          Paint()
            ..shader = shader
            ..filterQuality = FilterQuality.none,
        );
        canvas.restore();
      }
      if (spec.borderColor != null && spec.borderWidth > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = spec.borderColor!
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.bevel
            ..strokeWidth = spec.borderWidth
            ..isAntiAlias = false,
        );
      }
    }
  }

  Path _pathForArea(AreaFeature area, List<Offset> outer) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addPolygon(outer, true);
    for (final hole in area.holes) {
      final projected = [
        for (final point in hole) camera.latLngToScreenOffset(point),
      ];
      if (projected.length >= 3) path.addPolygon(projected, true);
    }
    return path;
  }

  @override
  bool shouldRepaint(_TextureAreaBatchPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.areas != areas ||
      oldDelegate.images != images;
}
