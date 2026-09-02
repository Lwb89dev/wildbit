import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

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
  final Map<String, ui.Image> _images = {};
  // Replace this map atomically as assets arrive. Its stable identity between
  // image loads lets CustomPaint reject unrelated parent rebuilds (GPS, Bit or
  // UI state changes) instead of repainting all terrain polygons.
  Map<String, ui.Shader> _shaders = const {};
  final Set<String> _loading = {};
  _ProjectionKey? _projectionKey;
  List<_ProjectedTextureArea>? _projectedAreas;

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
    final key = _ProjectionKey.from(widget.camera, widget.areas);
    final cached = _projectedAreas;
    if (cached != null && key == _projectionKey) return cached;
    final projected = _projectAreas(widget.camera);
    _projectionKey = key;
    _projectedAreas = List.unmodifiable(projected);
    return _projectedAreas!;
  }

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

/// Exact camera/feature identity key for the screen-space polygon cache.
///
/// This deliberately does not quantise the camera: an actual pan, pinch or
/// rotation must reproject immediately. Area identities survive the filtered
/// temporary lists built by biome/geology layers, so an unrelated rebuild can
/// reuse the existing paths safely.
class _ProjectionKey {
  const _ProjectionKey({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.rotation,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.areaSignature,
  });

  factory _ProjectionKey.from(
    MapCamera camera,
    List<ProjectedTextureAreaSpec> areas,
  ) {
    final bounds = camera.visibleBounds;
    return _ProjectionKey(
      latitude: camera.center.latitude,
      longitude: camera.center.longitude,
      zoom: camera.zoom,
      rotation: camera.rotation,
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
      areaSignature: Object.hashAll([
        for (final spec in areas)
          Object.hash(
            identityHashCode(spec.area),
            spec.asset,
            spec.fallbackColor,
            spec.borderColor,
            spec.borderWidth,
          ),
      ]),
    );
  }

  final double latitude;
  final double longitude;
  final double zoom;
  final double rotation;
  final double south;
  final double west;
  final double north;
  final double east;
  final int areaSignature;

  @override
  bool operator ==(Object other) =>
      other is _ProjectionKey &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      zoom == other.zoom &&
      rotation == other.rotation &&
      south == other.south &&
      west == other.west &&
      north == other.north &&
      east == other.east &&
      areaSignature == other.areaSignature;

  @override
  int get hashCode => Object.hash(
    latitude,
    longitude,
    zoom,
    rotation,
    south,
    west,
    north,
    east,
    areaSignature,
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
}
