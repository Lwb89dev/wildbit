import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
import '../composition/map_geometry_rules.dart';
import '../composition/osm_line_projector.dart';
import '../performance/map_rendering_budget.dart';

/// Deterministic foreground vegetation generated from real area polygons.
/// It is decorative only: no generated sprite is used as a navigational POI.
class OsmPixelForegroundVegetationLayer extends StatefulWidget {
  const OsmPixelForegroundVegetationLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelForegroundVegetationLayer> createState() =>
      _OsmPixelForegroundVegetationLayerState();
}

class _OsmPixelForegroundVegetationLayerState
    extends State<OsmPixelForegroundVegetationLayer> {
  static const _candidateLimit = 220;
  static const _assets = [
    'assets/map/mock/objects/shrub_round.png',
    'assets/map/mock/objects/shrub_wide.png',
    'assets/map/mock/objects/shrub_riverside.png',
  ];

  List<_VegetationPoint> _candidates = const [];
  List<ui.Image> _images = const [];
  late int _featureSignature;
  Future<void>? _loading;

  @override
  void initState() {
    super.initState();
    _featureSignature = _signature(widget.features);
    _candidates = _composeCandidates();
  }

  @override
  void didUpdateWidget(covariant OsmPixelForegroundVegetationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.features);
    if (signature == _featureSignature) return;
    _featureSignature = signature;
    _candidates = _composeCandidates();
  }

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
      // Decorative assets must never make the navigational map unavailable.
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _resolveImage(String asset) {
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
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => RepaintBoundary(
          child: CustomPaint(
            size: constraints.biggest,
            painter: _VegetationPainter(
              camera: camera,
              candidates: _candidates,
              images: _images,
            ),
          ),
        ),
      ),
    );
  }

  List<_VegetationPoint> _composeCandidates() {
    final areas = widget.features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.forest ||
              area.kind == MapFeatureKind.meadow ||
              area.kind == MapFeatureKind.park,
        )
        .toList(growable: false);
    final result = <_VegetationPoint>[];
    if (areas.isNotEmpty) {
      // Give every polygon a fair share. A large first polygon must not starve
      // smaller parks that enter the viewport later.
      final perArea = math.max(18, (_candidateLimit / areas.length).ceil());
      for (final area in areas) {
        if (result.length >= _candidateLimit) break;
        result.addAll(
          _sample(area, math.min(perArea, _candidateLimit - result.length)),
        );
      }
    }
    if (result.length < _candidateLimit) {
      result.addAll(_sampleNearTrees(_candidateLimit - result.length));
    }
    return List.unmodifiable(result);
  }

  List<_VegetationPoint> _sample(
    AreaFeature area,
    int remaining,
  ) {
    if (area.ring.length < 3 || remaining <= 0) return const [];
    var south = area.ring.first.latitude;
    var north = south;
    var west = area.ring.first.longitude;
    var east = west;
    for (final point in area.ring.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    final random = math.Random(_seed(area));
    final result = <_VegetationPoint>[];
    for (var attempt = 0; attempt < remaining * 8 && result.length < remaining; attempt++) {
      final position = LatLng(
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      );
      if (!MapGeometryRules.pointInPolygon(position, area.ring) ||
          MapGeometryRules.insideAnyWater(position, widget.features.areas) ||
          MapGeometryRules.nearAnyLine(position, widget.features.lines)) {
        continue;
      }
      if (random.nextDouble() > MapRenderingBudget.biomeDensity(area.kind)) {
        continue;
      }
      final edgeScale = MapGeometryRules.nearPolygonBoundary(
        position,
        area.ring,
        thresholdDegrees: .0003,
      )
          ? .7
          : 1.0;
      result.add(
        _VegetationPoint(position, random.nextInt(3), edgeScale),
      );
    }
    return result;
  }

  List<_VegetationPoint> _sampleNearTrees(int remaining) {
    final trees = widget.features.pois
        .where((poi) => poi.type == PoiType.tree)
        .toList(growable: false);
    final result = <_VegetationPoint>[];
    for (var i = 0; i < trees.length && result.length < remaining; i++) {
      final tree = trees[i];
      final seed = tree.id.hashCode ^ (i * 7919);
      final latOffset = (((seed.abs() % 100) / 100) - .5) * .00065;
      final lonOffset = ((((seed ~/ 101).abs() % 100) / 100) - .5) * .00065;
      final point = LatLng(
        tree.position.latitude + latOffset,
        tree.position.longitude + lonOffset,
      );
      if (MapGeometryRules.insideAnyWater(point, widget.features.areas) ||
          MapGeometryRules.nearAnyLine(
            point,
            widget.features.lines,
            thresholdDegrees: .00022,
          )) {
        continue;
      }
      result.add(_VegetationPoint(point, seed.abs() % 3, .86));
    }
    return result;
  }

  int _seed(AreaFeature area) {
    var value = area.sourceId?.hashCode ?? area.ring.length;
    for (final point in area.ring) {
      value = value * 31 + point.latitude.hashCode;
      value = value * 31 + point.longitude.hashCode;
    }
    return value;
  }

  int _signature(MapFeatureCollection features) => Object.hash(
        Object.hashAll(
          features.areas.map((area) => area.sourceId ?? _seed(area)),
        ),
        Object.hashAll(
          features.lines.map((line) => OsmLineProjector.seedFor(line)),
        ),
        Object.hashAll(features.pois.map((poi) => poi.id)),
      );
}

class _VegetationPoint {
  const _VegetationPoint(
    this.position,
    this.variant,
    this.scaleMultiplier,
  );

  final LatLng position;
  final int variant;
  final double scaleMultiplier;
}

class _VegetationPainter extends CustomPainter {
  const _VegetationPainter({
    required this.camera,
    required this.candidates,
    required this.images,
  });

  final MapCamera camera;
  final List<_VegetationPoint> candidates;
  final List<ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    final points = candidates
        .where((point) => camera.visibleBounds.contains(point.position))
        .toList(growable: false);
    // South is visually closer on a north-up map. Paint it last so foreground
    // shrubs naturally overlap background shrubs and tree trunks.
    points.sort((a, b) => b.position.latitude.compareTo(a.position.latitude));
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .35,
      max: 1.0,
    );
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (final point in points) {
      final foot = camera.latLngToScreenOffset(point.position);
      final dimension = 25 * scale * point.scaleMultiplier;
      if (foot.dx < -dimension ||
          foot.dy < -dimension ||
          foot.dx > size.width + dimension ||
          foot.dy > size.height + dimension) {
        continue;
      }
      if (images.isEmpty) {
        canvas.drawCircle(
          foot.translate(0, -dimension * .32),
          dimension * .3,
          Paint()..color = const Color(0xFF4D7C35),
        );
        continue;
      }
      final image = images[point.variant % images.length];
      final imageScale = math.min(
        dimension / image.width,
        dimension / image.height,
      );
      final width = image.width * imageScale;
      final height = image.height * imageScale;
      final target = Rect.fromLTWH(
        foot.dx - width / 2,
        foot.dy - height,
        width,
        height,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        target,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VegetationPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.candidates != candidates ||
      oldDelegate.images != images;
}
