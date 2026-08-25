import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/map_geometry_rules.dart';
import '../composition/osm_water_polygon_projector.dart';
import '../composition/water_edge_composer.dart';
import '../performance/map_rendering_budget.dart';

/// Batched production pass for OSM water polygons, shores and riparian detail.
/// One animation clock and one Canvas replace the previous timer, clip tree and
/// set of image widgets allocated for every visible lake or pond.
class OsmPixelWaterLayer extends StatefulWidget {
  const OsmPixelWaterLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelWaterLayer> createState() => _OsmPixelWaterLayerState();
}

class _OsmPixelWaterLayerState extends State<OsmPixelWaterLayer>
    with WidgetsBindingObserver {
  static const _flowStep = Duration(milliseconds: 140);
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

  final ValueNotifier<double> _flowPhase = ValueNotifier(0);
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  Timer? _flowTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startFlow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final asset in _assets) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Future<void> _loadImage(String asset) async {
    final completer = Completer<ui.Image>();
    final stream = AssetImage(asset).resolve(
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
      if (mounted) setState(() => _images[asset] = image);
    } catch (_) {
      // Solid water and geometric shore fallbacks remain available.
    } finally {
      _loading.remove(asset);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startFlow();
    } else {
      _flowTimer?.cancel();
      _flowTimer = null;
    }
  }

  void _startFlow() {
    if (_flowTimer?.isActive ?? false) return;
    _flowTimer = Timer.periodic(_flowStep, (_) {
      _flowPhase.value = (_flowPhase.value + 1 / 20) % 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flowTimer?.cancel();
    _flowPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final waterAreas = widget.features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.water &&
              MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds),
        )
        .toList()
      ..sort(
        (a, b) => MapGeometryRules.polygonArea(b.ring).compareTo(
          MapGeometryRules.polygonArea(a.ring),
        ),
      );
    final scale = _scaleForZoom(camera.zoom);
    final renders = <_WaterAreaRender>[];
    for (final area in waterAreas) {
      final polygon = OsmWaterPolygonProjector.project(
        area,
        camera.latLngToScreenOffset,
      );
      if (polygon.length < 3) continue;
      final material = _materialFor(area);
      final seed = OsmWaterPolygonProjector.seedFor(area);
      renders.add(
        _WaterAreaRender(
          polygon: polygon,
          material: material,
          seed: seed,
          edges: WaterEdgeComposer(
            spacing: 28 * scale,
            maxPlacements: MapRenderingBudget.maxShoreSpritesPerPolygon,
            fixedPlacements: _shorePlacementCount(area),
          ).compose(
            polygon: polygon,
            material: material,
            chunkSeed: seed,
          ),
        ),
      );
    }
    if (renders.isEmpty) return const SizedBox.expand();
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _flowPhase,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _WaterBatchPainter(
              renders: renders,
              images: Map.unmodifiable(_images),
              phase: _flowPhase.value,
              scale: scale,
            ),
          ),
        ),
      ),
    );
  }

  double _scaleForZoom(double zoom) =>
      math.pow(2, zoom - 16).clamp(.65, 1.35).toDouble();

  int _shorePlacementCount(AreaFeature water) {
    if (water.ring.length < 3) return 0;
    var perimeter = 0.0;
    for (var index = 0; index < water.ring.length; index++) {
      final start = water.ring[index];
      final end = water.ring[(index + 1) % water.ring.length];
      final latitudeScale = math.cos(
        (start.latitude + end.latitude) * math.pi / 360,
      );
      final dy = end.latitude - start.latitude;
      final dx = (end.longitude - start.longitude) * latitudeScale;
      perimeter += math.sqrt(dx * dx + dy * dy);
    }
    return (perimeter / .00038)
        .round()
        .clamp(4, MapRenderingBudget.maxShoreSpritesPerPolygon);
  }

  WaterEdgeMaterial _materialFor(AreaFeature water) {
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
    required this.polygon,
    required this.material,
    required this.seed,
    required this.edges,
  });

  final List<Offset> polygon;
  final WaterEdgeMaterial material;
  final int seed;
  final List<WaterEdgePlacement> edges;
}

class _WaterBatchPainter extends CustomPainter {
  const _WaterBatchPainter({
    required this.renders,
    required this.images,
    required this.phase,
    required this.scale,
  });

  final List<_WaterAreaRender> renders;
  final Map<String, ui.Image> images;
  final double phase;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final shaders = <String, ui.Shader>{
      for (final entry in images.entries.where(
        (entry) => entry.key.contains('water_still_'),
      ))
        entry.key: ui.ImageShader(
          entry.value,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Float64List.fromList(const [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
          filterQuality: ui.FilterQuality.none,
        ),
    };

    // All water fills are composed first. Shore modules can then form one
    // clean foreground edge without being covered by a later pond polygon.
    for (final render in renders) {
      final path = Path()..addPolygon(render.polygon, true);
      final bounds = path.getBounds();
      if (bounds.isEmpty || !bounds.overlaps(Offset.zero & size)) continue;
      final asset =
          'assets/map/mock/terrain/water_still_${render.seed.abs() % 3 + 1}.png';
      final shader = shaders[asset];
      if (shader == null) {
        canvas.drawPath(path, Paint()..color = const Color(0xFF3987A3));
        continue;
      }
      canvas.save();
      canvas.clipPath(path);
      canvas.translate(bounds.left - 16 * phase, bounds.top);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, bounds.width + 16, bounds.height),
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.none,
      );
      canvas.restore();
      _paintWaterHighlights(canvas, path, bounds, render.seed, size);
    }

    for (final render in renders) {
      final shorePath = Path()..addPolygon(render.polygon, true);
      _paintContinuousShore(canvas, shorePath, render.material);
      final shoreAsset = switch (render.material) {
        WaterEdgeMaterial.grass =>
          'assets/map/mock/terrain/shore_grass.png',
        WaterEdgeMaterial.rock =>
          'assets/map/mock/terrain/shore_rock_detail.png',
        WaterEdgeMaterial.sand =>
          'assets/map/mock/terrain/shore_sand_bank.png',
        WaterEdgeMaterial.mud =>
          'assets/map/mock/terrain/shore_mud_bank.png',
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

  void _paintWaterHighlights(
    Canvas canvas,
    Path path,
    Rect bounds,
    int seed,
    Size canvasSize,
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
    for (var y = visible.top + seedOffset % spacingY;
        y < visible.bottom;
        y += spacingY) {
      final row = ((y - bounds.top) / spacingY).floor();
      final rowOffset = ((row * 19 + seed.abs()) % 31) * scale;
      for (var x = visible.left - spacingX + rowOffset;
          x < visible.right;
          x += spacingX) {
        final waveWidth = (8 + ((row + seed) & 7)) * scale;
        final pixel = math.max(1.0, 1.35 * scale);
        canvas.drawRect(
          Rect.fromLTWH(x + 2 * scale, y + 2 * scale, waveWidth, pixel),
          shade,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, y, waveWidth, pixel),
          light,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            x + waveWidth * .28,
            y - pixel,
            waveWidth * .44,
            pixel,
          ),
          light,
        );
      }
    }
    canvas.restore();
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
    if (material != WaterEdgeMaterial.mud) {
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
      Rect.fromCenter(
        center: Offset.zero,
        width: width,
        height: height,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaterBatchPainter oldDelegate) =>
      oldDelegate.renders != renders ||
      oldDelegate.images != images ||
      oldDelegate.phase != phase ||
      oldDelegate.scale != scale;
}
