import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../domain/entities/area_feature.dart';
import '../assets/map_visual_asset_warmup.dart';
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
  // Translating Path objects has a fixed allocation cost. It only wins once
  // an OSM land-cover batch is sufficiently complex; small local parks and
  // the lightweight profile fixture are faster to project directly.
  static const _translationReuseMinimumVertices = 160;
  final Map<String, ui.Image> _images = {};
  // Replace this map atomically as assets arrive. Its stable identity between
  // image loads lets CustomPaint reject unrelated parent rebuilds (GPS, Bit or
  // UI state changes) instead of repainting all terrain polygons.
  Map<String, ui.Shader> _shaders = const {};
  final Set<String> _loading = {};
  _TextureProjectionCache? _projectionCache;

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
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _TextureAreaBatchPainter(
        camera: widget.camera,
        areas: _projectAreasForCurrentView(),
        shaders: widget.textureEnabled ? _shaders : const <String, ui.Shader>{},
      ),
    ),
  );

  List<_ProjectedTextureArea> _projectAreasForCurrentView() {
    final signature = _areaSignature(widget.areas);
    final anchor = _anchorFor(widget.areas);
    final vertexCount = _vertexCount(widget.areas);
    final cached = _projectionCache;
    if (cached != null && cached.areaSignature == signature) {
      if (cached.matches(widget.camera, anchor)) return cached.areas;
      // A pan at fixed zoom and rotation is a plain screen-space
      // translation in FlutterMap's projected plane. Reusing the already
      // clipped paths avoids rebuilding hundreds of polygon vertices while
      // preserving the exact textured material (so forest/rock areas do not
      // flash into a flat fallback while the finger is down).
      if (anchor != null &&
          vertexCount >= _translationReuseMinimumVertices &&
          cached.canTranslateTo(widget.camera)) {
        final nextAnchor = widget.camera.latLngToScreenOffset(anchor);
        final delta = nextAnchor - cached.anchorScreen;
        if (delta != Offset.zero) {
          _projectionCache = cached.shifted(
            delta: delta,
            anchorScreen: nextAnchor,
            camera: widget.camera,
          );
        }
        return _projectionCache!.areas;
      }
    }
    final projected = _projectAreas(widget.camera);
    _projectionCache = _TextureProjectionCache(
      areaSignature: signature,
      zoom: widget.camera.zoom,
      rotation: widget.camera.rotation,
      anchorScreen: anchor == null
          ? Offset.zero
          : widget.camera.latLngToScreenOffset(anchor),
      areas: List.unmodifiable(projected),
    );
    return _projectionCache!.areas;
  }

  int _areaSignature(List<ProjectedTextureAreaSpec> areas) => Object.hashAll([
    for (final spec in areas)
      Object.hash(
        identityHashCode(spec.area),
        spec.asset,
        spec.fallbackColor,
        spec.borderColor,
        spec.borderWidth,
      ),
  ]);

  LatLng? _anchorFor(List<ProjectedTextureAreaSpec> areas) {
    for (final spec in areas) {
      if (spec.area.ring.isNotEmpty) return spec.area.ring.first;
    }
    return null;
  }

  int _vertexCount(List<ProjectedTextureAreaSpec> areas) => areas.fold(
    0,
    (count, spec) =>
        count +
        spec.area.ring.length +
        spec.area.holes.fold<int>(0, (sum, hole) => sum + hole.length),
  );

  List<_ProjectedTextureArea> _projectAreas(MapCamera camera) {
    final projected = <_ProjectedTextureArea>[];
    for (final spec in widget.areas) {
      final polygon = OsmWaterPolygonProjector.project(
        spec.area,
        camera.latLngToScreenOffset,
      );
      if (polygon.length < 3) continue;
      final holes = [
        for (final hole in spec.area.holes)
          OsmWaterPolygonProjector.projectRing(
            hole,
            camera.latLngToScreenOffset,
          ),
      ];
      final path = Path()..fillType = PathFillType.evenOdd;
      path.addPolygon(polygon, true);
      for (final hole in holes) {
        if (hole.length >= 3) path.addPolygon(hole, true);
      }
      projected.add(
        _ProjectedTextureArea(
          path: path,
          bounds: path.getBounds(),
          asset: spec.asset,
          fallbackColor: spec.fallbackColor,
          borderColor: spec.borderColor,
          borderWidth: spec.borderWidth,
        ),
      );
    }
    return projected;
  }
}

/// Cached projected area paths. Pure pans retain their scale and rotation, so
/// the whole batch can be shifted from a single stable geographic anchor.
/// Zooms, rotations and changes to the visible area set still reproject from
/// source geometry immediately.
class _TextureProjectionCache {
  const _TextureProjectionCache({
    required this.areaSignature,
    required this.zoom,
    required this.rotation,
    required this.anchorScreen,
    required this.areas,
  });

  final int areaSignature;
  final double zoom;
  final double rotation;
  final Offset anchorScreen;
  final List<_ProjectedTextureArea> areas;

  bool matches(MapCamera camera, LatLng? anchor) =>
      anchor != null &&
      zoom == camera.zoom &&
      rotation == camera.rotation &&
      anchorScreen == camera.latLngToScreenOffset(anchor);

  bool canTranslateTo(MapCamera camera) =>
      zoom == camera.zoom && rotation == camera.rotation;

  _TextureProjectionCache shifted({
    required Offset delta,
    required Offset anchorScreen,
    required MapCamera camera,
  }) => _TextureProjectionCache(
    areaSignature: areaSignature,
    zoom: camera.zoom,
    rotation: camera.rotation,
    anchorScreen: anchorScreen,
    areas: List.unmodifiable([for (final area in areas) area.shifted(delta)]),
  );
}

class _TextureAreaBatchPainter extends CustomPainter {
  const _TextureAreaBatchPainter({
    required this.camera,
    required this.areas,
    required this.shaders,
  });

  final MapCamera camera;
  final List<_ProjectedTextureArea> areas;
  final Map<String, ui.Shader> shaders;

  @override
  void paint(Canvas canvas, Size size) {
    for (final spec in areas) {
      final path = spec.path;
      final bounds = spec.bounds;
      if (bounds.isEmpty || !bounds.overlaps(Offset.zero & size)) continue;
      final visible = bounds.intersect(Offset.zero & size);
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
  }

  @override
  bool shouldRepaint(_TextureAreaBatchPainter oldDelegate) =>
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

  _ProjectedTextureArea shifted(Offset delta) => _ProjectedTextureArea(
    path: path.shift(delta),
    bounds: bounds.shift(delta),
    asset: asset,
    fallbackColor: fallbackColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
  );
}
