import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/map_geometry_rules.dart';
import '../composition/osm_water_polygon_projector.dart';
import '../composition/water_edge_composer.dart';
import '../performance/map_rendering_budget.dart';

/// Batched production pass for OSM water polygons, shores and riparian detail.
/// The static fill/bank pass is split from the sparse animated highlights, so
/// a large lake does not repaint its whole texture on every ambient tick.
class OsmPixelWaterLayer extends StatefulWidget {
  const OsmPixelWaterLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelWaterLayer> createState() => _OsmPixelWaterLayerState();
}

class _OsmPixelWaterLayerState extends State<OsmPixelWaterLayer> {
  static const _assets = [
    'assets/map/mock/terrain/water_still_1.png',
    'assets/map/mock/terrain/water_still_2.png',
    'assets/map/mock/terrain/water_still_3.png',
    'assets/map/mock/terrain/shore_grass.png',
    'assets/map/mock/terrain/shore_rock_detail.png',
    'assets/map/mock/terrain/shore_sand_bank.png',
    'assets/map/mock/terrain/shore_mud_bank.png',
    'assets/map/mock/objects/shrub_riverside.png',
  ];

  // These maps are replaced atomically when an asset becomes available. Their
  // identities stay stable during GPS/UI rebuilds, so an otherwise static
  // lake does not repaint merely because a parent widget rebuilt.
  Map<String, ui.Image> _images = const {};
  Map<String, ui.Shader> _shaders = const {};
  final Set<String> _loading = {};
  final Map<AreaFeature, WaterEdgeMaterial> _materialCache = {};
  int? _renderViewKey;
  List<_WaterAreaRender>? _cachedRenders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant OsmPixelWaterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      // Rock adjacency is geographic data, not camera state. Reuse it while
      // the user pans/zooms, but discard it as soon as a new OSM snapshot
      // arrives so a refreshed coastline cannot inherit stale bank material.
      _materialCache.clear();
      _renderViewKey = null;
      _cachedRenders = null;
    }
    _ensureImages();
  }

  void _ensureImages() {
    if (!widget.features.areas.any(
      (area) => area.kind == MapFeatureKind.water,
    )) {
      return;
    }
    for (final asset in _assets) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Future<void> _loadImage(String asset) async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, asset);
      if (mounted) {
        setState(() {
          _images = Map.unmodifiable({..._images, asset: image});
          if (asset.contains('water_still_')) {
            _shaders = Map.unmodifiable({
              ..._shaders,
              asset: _shaderFor(image),
            });
          }
        });
      }
    } catch (_) {
      // Solid water and geometric shore fallbacks remain available.
    } finally {
      _loading.remove(asset);
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
    final renders = _rendersForCamera(camera);
    if (renders.isEmpty) return const SizedBox.expand();
    final scale = _scaleForZoom(camera.zoom);
    final showAmbientDetails =
        MapRenderingBudget.ambientDetailEnabled &&
        !MapRenderingBudget.mapInteracting;
    // Most of a lake/sea frame is geographically static.  Keeping the fill,
    // banks and shore modules in their own repaint boundary prevents the
    // ambient clock from re-rasterising every water polygon just to move a
    // handful of subtle highlights.
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaterBasePainter(
                renders: renders,
                // Do not trade the static water material for a solid fallback
                // while the user is panning. Apart from the visible blue
                // flash this made a moving river expose a different surface
                // from the same river at rest. The expensive animated pass
                // and bank sprites remain suspended below; the tiled base is
                // cached and is the visual continuity anchor.
                images: _images,
                shaders: _shaders,
                scale: scale,
                showBankSprites: showAmbientDetails,
              ),
            ),
          ),
          if (showAmbientDetails)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: MapRenderingBudget.ambientClock,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _WaterAmbientPainter(
                    renders: renders,
                    phase: MapRenderingBudget.ambientClock.phase,
                    scale: scale,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_WaterAreaRender> _rendersForCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final scale = _scaleForZoom(camera.zoom);
    final viewKey = Object.hash(
      identityHashCode(widget.features),
      camera.center.latitude,
      camera.center.longitude,
      camera.zoom,
      camera.rotation,
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      scale,
      MapRenderingBudget.decorativeQuality,
    );
    final cached = _cachedRenders;
    if (cached != null && _renderViewKey == viewKey) return cached;
    final waterAreas =
        widget.features.areas
            .where(
              (area) =>
                  area.kind == MapFeatureKind.water &&
                  MapRenderingBudget.areaMayBeVisible(
                    area,
                    camera.visibleBounds,
                  ),
            )
            .toList()
          ..sort(
            (a, b) => MapGeometryRules.polygonArea(
              b.ring,
            ).compareTo(MapGeometryRules.polygonArea(a.ring)),
          );
    final renders = <_WaterAreaRender>[];
    for (final area in waterAreas) {
      final polygon = OsmWaterPolygonProjector.project(
        area,
        camera.latLngToScreenOffset,
      );
      if (polygon.length < 3) continue;
      final material = _materialFor(area);
      final seed = OsmWaterPolygonProjector.seedFor(area);
      final projectedHoles = [
        for (final hole in area.holes)
          OsmWaterPolygonProjector.projectRing(
            hole,
            camera.latLngToScreenOffset,
          ),
      ];
      final path = Path()..fillType = PathFillType.evenOdd;
      path.addPolygon(polygon, true);
      for (final hole in projectedHoles) {
        if (hole.length >= 3) path.addPolygon(hole, true);
      }
      renders.add(
        _WaterAreaRender(
          path: path,
          bounds: path.getBounds(),
          material: material,
          seed: seed,
          edges: _shorePlacements(
            area: area,
            outer: polygon,
            holes: projectedHoles,
            material: material,
            seed: seed,
            scale: scale,
          ),
        ),
      );
    }
    _renderViewKey = viewKey;
    _cachedRenders = List.unmodifiable(renders);
    return _cachedRenders!;
  }

  double _scaleForZoom(double zoom) =>
      math.pow(2, zoom - 16).clamp(.65, 1.35).toDouble();

  int _shorePlacementCount(AreaFeature water) {
    var perimeter = 0.0;
    for (final ring in [water.ring, ...water.holes]) {
      if (ring.length < 3) continue;
      for (var index = 0; index < ring.length; index++) {
        final start = ring[index];
        final end = ring[(index + 1) % ring.length];
        final latitudeScale = math.cos(
          (start.latitude + end.latitude) * math.pi / 360,
        );
        final dy = end.latitude - start.latitude;
        var longitudeDelta = end.longitude - start.longitude;
        if (longitudeDelta > 180) longitudeDelta -= 360;
        if (longitudeDelta < -180) longitudeDelta += 360;
        final dx = longitudeDelta * latitudeScale;
        perimeter += math.sqrt(dx * dx + dy * dy);
      }
    }
    final requested = (perimeter / .00038).round().clamp(
      4,
      MapRenderingBudget.maxShoreSpritesPerPolygon,
    );
    return MapRenderingBudget.shoreDetailCount(requested);
  }

  List<WaterEdgePlacement> _shorePlacements({
    required AreaFeature area,
    required List<Offset> outer,
    required List<List<Offset>> holes,
    required WaterEdgeMaterial material,
    required int seed,
    required double scale,
  }) {
    final rings = [outer, ...holes];
    final total = _projectedPerimeter(rings);
    if (total == 0) return const [];
    var remaining = _shorePlacementCount(area);
    final placements = <WaterEdgePlacement>[];
    for (var index = 0; index < rings.length && remaining > 0; index++) {
      final ring = rings[index];
      if (ring.length < 3) continue;
      final isLast = index == rings.length - 1;
      final count = isLast
          ? remaining
          : math
                .max(
                  1,
                  (remaining * _projectedPerimeter([ring]) / total).round(),
                )
                .clamp(1, remaining);
      remaining -= count;
      final ringPlacements =
          WaterEdgeComposer(
            spacing: 28 * scale,
            maxPlacements: count,
            fixedPlacements: count,
          ).compose(
            polygon: ring,
            material: material,
            chunkSeed: seed + index * 101,
          );
      if (index == 0) {
        placements.addAll(ringPlacements);
      } else {
        // An inner ring bounds land, so its land/water normal is the inverse
        // of the one used by an ordinary water-inside ring.
        placements.addAll(
          ringPlacements.map(
            (edge) => WaterEdgePlacement(
              position: edge.position - edge.normal * 6,
              tangent: edge.tangent,
              normal: -edge.normal,
              material: edge.material,
              variant: edge.variant,
            ),
          ),
        );
      }
    }
    return placements;
  }

  double _projectedPerimeter(List<List<Offset>> rings) {
    var total = 0.0;
    for (final ring in rings) {
      for (var index = 0; index < ring.length; index++) {
        total += (ring[(index + 1) % ring.length] - ring[index]).distance;
      }
    }
    return total;
  }

  WaterEdgeMaterial _materialFor(AreaFeature water) =>
      _materialCache.putIfAbsent(water, () => _computeMaterial(water));

  WaterEdgeMaterial _computeMaterial(AreaFeature water) {
    for (final terrain in widget.features.areas) {
      if (terrain.kind != MapFeatureKind.mountainRock) continue;
      for (final point in water.ring) {
        if (MapGeometryRules.pointInPolygon(point, terrain.ring) ||
            MapGeometryRules.nearPolygonBoundary(
              point,
              terrain.ring,
              thresholdDegrees: .00055,
            )) {
          return WaterEdgeMaterial.rock;
        }
      }
    }
    // Closed water areas represent lakes/ponds in the current feature model;
    // use a sandy transition unless an adjacent rock area overrides it.
    return WaterEdgeMaterial.sand;
  }
}

class _WaterAreaRender {
  const _WaterAreaRender({
    required this.path,
    required this.bounds,
    required this.material,
    required this.seed,
    required this.edges,
  });

  final Path path;
  final Rect bounds;
  final WaterEdgeMaterial material;
  final int seed;
  final List<WaterEdgePlacement> edges;
}

class _WaterBasePainter extends CustomPainter {
  const _WaterBasePainter({
    required this.renders,
    required this.images,
    required this.shaders,
    required this.scale,
    required this.showBankSprites,
  });

  final List<_WaterAreaRender> renders;
  final Map<String, ui.Image> images;
  final Map<String, ui.Shader> shaders;
  final double scale;
  final bool showBankSprites;

  @override
  void paint(Canvas canvas, Size size) {
    // All water fills are composed first. Shore modules can then form one
    // clean foreground edge without being covered by a later pond polygon.
    for (final render in renders) {
      final path = render.path;
      final bounds = render.bounds;
      if (bounds.isEmpty || !bounds.overlaps(Offset.zero & size)) continue;
      final visible = bounds.intersect(Offset.zero & size);
      if (visible.isEmpty) continue;
      final asset =
          'assets/map/mock/terrain/water_still_${render.seed.abs() % 3 + 1}.png';
      final shader = shaders[asset];
      if (shader == null) {
        canvas.drawPath(path, Paint()..color = const Color(0xFF3987A3));
        continue;
      }
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.none,
      );
    }

    for (final render in renders) {
      _paintContinuousShore(canvas, render.path, render.material);
      if (!showBankSprites) continue;
      final shoreAsset = switch (render.material) {
        WaterEdgeMaterial.grass => 'assets/map/mock/terrain/shore_grass.png',
        WaterEdgeMaterial.rock =>
          'assets/map/mock/terrain/shore_rock_detail.png',
        WaterEdgeMaterial.sand => 'assets/map/mock/terrain/shore_sand_bank.png',
        WaterEdgeMaterial.mud => 'assets/map/mock/terrain/shore_mud_bank.png',
      };
      final shore = images[shoreAsset];
      for (var index = 0; index < render.edges.length; index++) {
        final edge = render.edges[index];
        if (shore == null) {
          canvas.drawCircle(
            edge.position,
            3 * scale,
            Paint()
              ..color = switch (render.material) {
                WaterEdgeMaterial.rock => const Color(0xFF70695E),
                WaterEdgeMaterial.sand => const Color(0xFFD8AE68),
                WaterEdgeMaterial.mud => const Color(0xFF725238),
                WaterEdgeMaterial.grass => const Color(0xFF567D3E),
              },
          );
        } else {
          _drawSprite(
            canvas,
            shore,
            center: edge.position,
            width: 16 * scale,
            height: 16 * scale,
            // The authored tile has land on its left and water on its right.
            // Align local +X toward water (-normal), not along the tangent.
            angle: math.atan2(-edge.normal.dy, -edge.normal.dx),
          );
        }
        if (render.material != WaterEdgeMaterial.grass ||
            (index + edge.variant) % 5 != 0) {
          continue;
        }
        final shrub = images['assets/map/mock/objects/shrub_riverside.png'];
        if (shrub == null) continue;
        _drawSprite(
          canvas,
          shrub,
          center: edge.position + edge.normal * 8 * scale,
          width: 14 * scale,
          height: 14 * scale,
        );
      }
    }
  }

  void _paintContinuousShore(
    Canvas canvas,
    Path path,
    WaterEdgeMaterial material,
  ) {
    final materialColor = switch (material) {
      WaterEdgeMaterial.grass => const Color(0xFF6F803D),
      WaterEdgeMaterial.rock => const Color(0xFF777169),
      WaterEdgeMaterial.sand => const Color(0xFFD8AE68),
      WaterEdgeMaterial.mud => const Color(0xFF725238),
    };
    final outerColor = switch (material) {
      WaterEdgeMaterial.mud => const Color(0xFF503522),
      WaterEdgeMaterial.sand => const Color(0xFFB4874A),
      _ => const Color(0xFF294A46),
    };
    if (material == WaterEdgeMaterial.mud) {
      // The mud module is intentionally irregular and has transparent
      // margins. Seal the projected polygon first so those margins cannot
      // reveal a green terrain strip at the waterline.
      canvas.drawPath(
        path,
        Paint()
          ..color = materialColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(5, 7 * scale)
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = false,
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = outerColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.bevel
          ..strokeWidth = 2.5 * scale
          ..isAntiAlias = false,
      );
    }
    if (material != WaterEdgeMaterial.mud) {
      canvas.drawPath(
        path,
        Paint()
          ..color = materialColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.bevel
          ..strokeWidth = 1.5 * scale
          ..isAntiAlias = false,
      );
    }
    // Mud must touch the water directly. This pale highlight is only valid
    // for sand/grass/rock shores; on a river it produces a detached green
    // strip between the bank and the water texture.
    if (material != WaterEdgeMaterial.mud) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFB9E1DC)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.bevel
          ..strokeWidth = math.max(1, .6 * scale)
          ..isAntiAlias = false,
      );
    }
  }

  void _drawSprite(
    Canvas canvas,
    ui.Image image, {
    required Offset center,
    required double width,
    required double height,
    double angle = 0,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (angle != 0) canvas.rotate(angle);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaterBasePainter oldDelegate) =>
      oldDelegate.renders != renders ||
      oldDelegate.images != images ||
      oldDelegate.shaders != shaders ||
      oldDelegate.scale != scale ||
      oldDelegate.showBankSprites != showBankSprites;
}

/// Only the tiny lake/sea highlights repaint with the ambient clock.  The
/// textured water fill and all shore geometry stay in [_WaterBasePainter].
class _WaterAmbientPainter extends CustomPainter {
  const _WaterAmbientPainter({
    required this.renders,
    required this.phase,
    required this.scale,
  });

  final List<_WaterAreaRender> renders;
  final double phase;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final render in renders) {
      if (!render.bounds.overlaps(Offset.zero & size)) continue;
      _paintWaterHighlights(
        canvas,
        render.path,
        render.bounds,
        render.seed,
        size,
        phase,
        scale,
      );
    }
  }

  @override
  bool shouldRepaint(_WaterAmbientPainter oldDelegate) =>
      oldDelegate.renders != renders ||
      oldDelegate.phase != phase ||
      oldDelegate.scale != scale;
}

void _paintWaterHighlights(
  Canvas canvas,
  Path path,
  Rect bounds,
  int seed,
  Size canvasSize,
  double phase,
  double scale,
) {
  final visible = bounds.intersect(Offset.zero & canvasSize);
  if (visible.isEmpty) return;
  final spacingY = 25 * scale;
  final spacingX = 54 * scale;
  final light = Paint()
    ..color = const Color(0x99BFE8E5)
    ..isAntiAlias = false;
  final shade = Paint()
    ..color = const Color(0x55305F78)
    ..isAntiAlias = false;
  canvas.save();
  canvas.clipPath(path);
  final seedOffset = (seed.abs() % 17) * scale;
  final phaseOffset = phase * spacingX;
  for (
    var y = visible.top + seedOffset % spacingY;
    y < visible.bottom;
    y += spacingY
  ) {
    final row = ((y - bounds.top) / spacingY).floor();
    final rowOffset = ((row * 19 + seed.abs()) % 31) * scale;
    for (
      var x = visible.left - spacingX + rowOffset + phaseOffset;
      x < visible.right + spacingX;
      x += spacingX
    ) {
      final waveWidth = (8 + ((row + seed) & 7)) * scale;
      final pixel = math.max(1.0, 1.35 * scale);
      canvas.drawRect(
        Rect.fromLTWH(x + 2 * scale, y + 2 * scale, waveWidth, pixel),
        shade,
      );
      canvas.drawRect(Rect.fromLTWH(x, y, waveWidth, pixel), light);
      canvas.drawRect(
        Rect.fromLTWH(x + waveWidth * .28, y - pixel, waveWidth * .44, pixel),
        light,
      );
    }
  }
  canvas.restore();
}
