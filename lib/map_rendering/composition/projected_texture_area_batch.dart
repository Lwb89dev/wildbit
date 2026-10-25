import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../domain/entities/area_feature.dart';
import '../assets/map_visual_asset_warmup.dart';
import 'osm_water_polygon_projector.dart';
import 'pan_projection_frame.dart';

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
    this.textureEnabled = true,
  });

  final MapCamera camera;
  final List<ProjectedTextureAreaSpec> areas;

  /// False while the camera is moving: polygons retain their semantic fill
  /// and borders, but avoid repeating texture shaders for the fast path.
  final bool textureEnabled;

  @override
  State<ProjectedTextureAreaBatch> createState() =>
      _ProjectedTextureAreaBatchState();
}

class _ProjectedTextureAreaBatchState extends State<ProjectedTextureAreaBatch> {
  final Map<String, ui.Image> _images = {};
  // Replace this map atomically as assets arrive. Its stable identity between
  // image loads lets CustomPaint reject unrelated parent rebuilds (GPS, Bit or
  // UI state changes) instead of repainting all terrain polygons.
  Map<String, ui.Shader> _shaders = const {};
  final Set<String> _loading = {};
  // Polygons projected into the current pan frame, keyed by OSM feature.
  // A pan paints them through one canvas translation; areas entering the
  // viewport are projected on demand.
  PanProjectionFrame? _frame;
  final Map<AreaFeature, _FramePolygon?> _framePolygons = {};
  Offset _offset = Offset.zero;
  List<ProjectedTextureAreaSpec>? _lastSpecs;
  Offset? _lastOffset;
  List<_ProjectedTextureArea> _lastAreas = const [];

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
    if (!widget.textureEnabled) return;
    for (final asset in widget.areas.map((area) => area.asset).toSet()) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Future<void> _loadImage(String asset) async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, asset);
      if (mounted) {
        setState(() {
          _images[asset] = image;
          // Creating image shaders in every paint was surprisingly costly on
          // mid-range Android GPUs. Texture assets are immutable, so one
          // repeat shader per asset can be safely retained for this layer.
          _shaders = Map.unmodifiable({
            ..._shaders,
            asset: ui.ImageShader(
              image,
              ui.TileMode.repeated,
              ui.TileMode.repeated,
              Float64List.fromList(const [
                1, 0, 0, 0, // row 1
                0, 1, 0, 0, // row 2
                0, 0, 1, 0, // row 3
                0, 0, 0, 1, // row 4
              ]),
              filterQuality: ui.FilterQuality.none,
            ),
          });
        });
      }
    } catch (_) {
      // Every spec supplies a semantically correct solid fallback.
    } finally {
      _loading.remove(asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = _projectAreasForCurrentView();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _TextureAreaBatchPainter(
          camera: widget.camera,
          offset: _offset,
          areas: areas,
          shaders: widget.textureEnabled
              ? _shaders
              : const <String, ui.Shader>{},
        ),
      ),
    );
  }

  List<_ProjectedTextureArea> _projectAreasForCurrentView() {
    final camera = widget.camera;
    final frame = _frame;
    // Polygons are keyed by feature and kept across data updates at the same
    // zoom; bound the cache so a long pan or follow session cannot keep every
    // polygon it ever passed.
    if (frame == null ||
        !frame.accepts(camera) ||
        _framePolygons.length > 4 * widget.areas.length + 64) {
      _frame = PanProjectionFrame(camera);
      _framePolygons.clear();
      _lastSpecs = null;
    }
    final offset = _offset = _frame!.offsetFor(camera);
    // A rebuild without camera motion (GPS, Bit or controls) keeps the list
    // identity, so CustomPaint can skip repainting every terrain polygon.
    if (offset == _lastOffset && _sameSpecs(_lastSpecs, widget.areas)) {
      return _lastAreas;
    }
    final projected = <_ProjectedTextureArea>[];
    for (final spec in widget.areas) {
      final area = spec.area;
      final polygon = _framePolygons.containsKey(area)
          ? _framePolygons[area]
          : _framePolygons[area] = _projectPolygon(area, camera, offset);
      if (polygon == null) continue;
      projected.add(
        _ProjectedTextureArea(
          path: polygon.path,
          bounds: polygon.bounds,
          asset: spec.asset,
          fallbackColor: spec.fallbackColor,
          borderColor: spec.borderColor,
          borderWidth: spec.borderWidth,
        ),
      );
    }
    _lastSpecs = widget.areas;
    _lastOffset = offset;
    return _lastAreas = List.unmodifiable(projected);
  }

  static bool _sameSpecs(
    List<ProjectedTextureAreaSpec>? previous,
    List<ProjectedTextureAreaSpec> next,
  ) {
    if (previous == null || previous.length != next.length) return false;
    for (var index = 0; index < next.length; index++) {
      final a = previous[index];
      final b = next[index];
      if (!identical(a.area, b.area) ||
          a.asset != b.asset ||
          a.fallbackColor != b.fallbackColor ||
          a.borderColor != b.borderColor ||
          a.borderWidth != b.borderWidth) {
        return false;
      }
    }
    return true;
  }

  static _FramePolygon? _projectPolygon(
    AreaFeature area,
    MapCamera camera,
    Offset offset,
  ) {
    Offset project(LatLng point) =>
        PanProjectionFrame.project(camera, offset, point);
    final polygon = OsmWaterPolygonProjector.project(area, project);
    if (polygon.length < 3) return null;
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addPolygon(polygon, true);
    for (final hole in area.holes) {
      final projectedHole = OsmWaterPolygonProjector.projectRing(hole, project);
      if (projectedHole.length >= 3) path.addPolygon(projectedHole, true);
    }
    return _FramePolygon(path, path.getBounds());
  }
}

class _FramePolygon {
  const _FramePolygon(this.path, this.bounds);

  final Path path;
  final Rect bounds;
}

class _TextureAreaBatchPainter extends CustomPainter {
  const _TextureAreaBatchPainter({
    required this.camera,
    required this.offset,
    required this.areas,
    required this.shaders,
  });

  final MapCamera camera;

  /// Translation from the polygons' pan frame to the screen.
  final Offset offset;
  final List<_ProjectedTextureArea> areas;
  final Map<String, ui.Shader> shaders;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = PanProjectionFrame.viewportIn(size, offset);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final spec in areas) {
      final path = spec.path;
      final bounds = spec.bounds;
      if (bounds.isEmpty || !bounds.overlaps(viewport)) continue;
      final visible = bounds.intersect(viewport);
      if (visible.isEmpty) continue;
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
          Rect.fromLTWH(
            visible.left - bounds.left,
            visible.top - bounds.top,
            visible.width,
            visible.height,
          ),
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextureAreaBatchPainter oldDelegate) =>
      oldDelegate.offset != offset ||
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.areas != areas ||
      oldDelegate.shaders != shaders;
}

class _ProjectedTextureArea {
  const _ProjectedTextureArea({
    required this.path,
    required this.bounds,
    required this.asset,
    required this.fallbackColor,
    this.borderColor,
    required this.borderWidth,
  });

  final Path path;
  final Rect bounds;
  final String asset;
  final Color fallbackColor;
  final Color? borderColor;
  final double borderWidth;
}
