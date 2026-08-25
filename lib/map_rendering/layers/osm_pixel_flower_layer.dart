import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/map_geometry_rules.dart';
import '../composition/osm_line_projector.dart';
import '../performance/map_rendering_budget.dart';

/// Tiny pixel flowers are decorative texture, never map evidence. Their
/// positions are sampled from meadow/park polygons and remain stable for a
/// given OSM feature, so panning does not make the scene shimmer.
class OsmPixelFlowerLayer extends StatefulWidget {
  const OsmPixelFlowerLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelFlowerLayer> createState() => _OsmPixelFlowerLayerState();
}

class _OsmPixelFlowerLayerState extends State<OsmPixelFlowerLayer>
    with WidgetsBindingObserver {
  static const _candidateLimit = 300;
  static const _windStep = Duration(milliseconds: 120);

  final ValueNotifier<double> _windPhase = ValueNotifier(0);
  List<_FlowerPoint> _candidates = const [];
  late int _featureSignature;
  Timer? _windTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _featureSignature = _signature(widget.features);
    _candidates = _composeCandidates();
    _startWind();
  }

  @override
  void didUpdateWidget(covariant OsmPixelFlowerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.features);
    if (signature == _featureSignature) return;
    _featureSignature = signature;
    _candidates = _composeCandidates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startWind();
    } else {
      _windTimer?.cancel();
      _windTimer = null;
    }
  }

  void _startWind() {
    if (_windTimer?.isActive ?? false) return;
    _windTimer = Timer.periodic(_windStep, (_) {
      // Pixel art benefits from deliberate stepped motion; eight updates per
      // second are enough and avoid forcing a permanent 60 fps map repaint.
      _windPhase.value = (_windPhase.value + 1 / 24) % 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _windTimer?.cancel();
    _windPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final budgeted = MapRenderingBudget.stableDecorativeSubset(
      _candidates,
      count: MapRenderingBudget.decorativeCount(
        camera.zoom,
        overview: 60,
        close: _candidates.length,
      ),
      rank: (flower) =>
          flower.position.latitude.hashCode ^
          flower.position.longitude.hashCode,
    );
    final flowers = budgeted
        .where((flower) => camera.visibleBounds.contains(flower.position))
        .toList(growable: false);
    flowers.sort((a, b) => b.position.latitude.compareTo(a.position.latitude));
    if (flowers.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => RepaintBoundary(
          child: AnimatedBuilder(
            animation: _windPhase,
            builder: (context, _) => CustomPaint(
              size: constraints.biggest,
              painter: _FlowerPainter(
                camera,
                flowers,
                constraints.biggest,
                _windPhase.value,
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isFlowerArea(AreaFeature area) =>
      area.kind == MapFeatureKind.meadow || area.kind == MapFeatureKind.park;

  List<_FlowerPoint> _composeCandidates() {
    final areas = widget.features.areas
        .where(_isFlowerArea)
        .toList(growable: false);
    if (areas.isEmpty) return const [];
    final result = <_FlowerPoint>[];
    final perArea = math.max(24, (_candidateLimit / areas.length).ceil());
    for (final area in areas) {
      if (result.length >= _candidateLimit) break;
      result.addAll(
        _sample(area, math.min(perArea, _candidateLimit - result.length)),
      );
    }
    return List.unmodifiable(result);
  }

  List<_FlowerPoint> _sample(AreaFeature area, int remaining) {
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
    final clusterCenters = [
      (
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      ),
      (
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      ),
      (
        south + random.nextDouble() * (north - south),
        west + random.nextDouble() * (east - west),
      ),
    ];
    final result = <_FlowerPoint>[];
    for (
      var attempt = 0;
      attempt < remaining * 10 && result.length < remaining;
      attempt++
    ) {
      final cluster = clusterCenters[random.nextInt(clusterCenters.length)];
      final position = LatLng(
        cluster.$1 + (random.nextDouble() - .5) * (north - south) * .28,
        cluster.$2 + (random.nextDouble() - .5) * (east - west) * .28,
      );
      if (!MapGeometryRules.pointInPolygon(position, area.ring) ||
          MapGeometryRules.insideAnyWater(position, widget.features.areas) ||
          MapGeometryRules.nearAnyLine(
            position,
            widget.features.lines,
            thresholdDegrees: .00018,
          )) {
        continue;
      }
      if (random.nextDouble() > MapRenderingBudget.biomeDensity(area.kind)) {
        continue;
      }
      result.add(_FlowerPoint(position, random.nextInt(4)));
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
    Object.hashAll(features.areas.map((area) => area.sourceId ?? _seed(area))),
    Object.hashAll(
      features.lines.map((line) => OsmLineProjector.seedFor(line)),
    ),
  );
}

class _FlowerPoint {
  const _FlowerPoint(this.position, this.variant);

  final LatLng position;
  final int variant;
}

class _FlowerPainter extends CustomPainter {
  const _FlowerPainter(this.camera, this.flowers, this.size, this.phase);

  final MapCamera camera;
  final List<_FlowerPoint> flowers;
  final Size size;
  final double phase;

  @override
  void paint(Canvas canvas, Size _) {
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .45,
      max: 1.0,
    );
    final stem = Paint()..color = const Color(0xFF47743A);
    const colors = [
      Color(0xFFF5D35B),
      Color(0xFFD979B7),
      Color(0xFFEDE9D5),
      Color(0xFFB58BDB),
    ];
    for (final flower in flowers) {
      final base = camera.latLngToScreenOffset(flower.position);
      // A continuous loop: the previous amplitude envelope jumped whenever
      // the controller wrapped from 1 back to 0.
      final sway =
          math.sin((phase * math.pi * 2) + flower.variant) * .65 * scale;
      final point = base.translate(sway, 0);
      if (point.dx < -8 ||
          point.dy < -8 ||
          point.dx > size.width + 8 ||
          point.dy > size.height + 8) {
        continue;
      }
      final stemHeight = 5 * scale;
      canvas.drawRect(
        Rect.fromLTWH(point.dx, point.dy - stemHeight, scale, stemHeight),
        stem,
      );
      final petal = Paint()..color = colors[flower.variant];
      final pixel = math.max(1.0, 2 * scale);
      canvas.drawRect(
        Rect.fromLTWH(
          point.dx - pixel,
          point.dy - stemHeight - pixel,
          pixel * 2,
          pixel * 2,
        ),
        petal,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          point.dx - pixel * .5,
          point.dy - stemHeight - pixel * 2,
          pixel,
          pixel,
        ),
        petal,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowerPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.flowers != flowers ||
      oldDelegate.phase != phase;
}
