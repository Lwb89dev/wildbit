import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../assets/map_visual_asset_warmup.dart';
import '../composition/pixel_bridge_geometry.dart';
import '../composition/pixel_bridge_placement.dart';
import '../composition/osm_water_polygon_projector.dart';
import '../composition/pan_projection_frame.dart';
import '../performance/map_rendering_budget.dart';

/// Batched bridge pass. A bridge is drawn only for an explicit OSM bridge
/// tag; artwork never asserts that a crossing is currently open or safe.
class OsmPixelBridgeLayer extends StatefulWidget {
  const OsmPixelBridgeLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  State<OsmPixelBridgeLayer> createState() => _OsmPixelBridgeLayerState();
}

class _OsmPixelBridgeLayerState extends State<OsmPixelBridgeLayer> {
  static const _assets = [
    // Keep the bridge as one watertight sprite. The former start/mid/end
    // canvases contain transparent perspective margins and become visibly
    // detached when stretched into narrow segments.
    'assets/map/mock/structures/bridge_foot_horizontal_v2.png',
  ];

  List<ui.Image> _images = const [];
  Future<void>? _loading;
  MapFeatureCollection? _bridgeSource;
  List<LineFeature> _bridgeLines = const [];
  // Bridges and water polygons projected into the current pan frame.
  PanProjectionFrame? _frame;
  final Map<AreaFeature, _BridgeWaterArea> _frameWater = {};
  final Map<LineFeature, (Offset, Offset)> _frameEndpoints = {};
  Offset _offset = Offset.zero;
  int? _placementKey;
  List<PixelBridgeGeometry> _geometries = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImages();
  }

  @override
  void didUpdateWidget(covariant OsmPixelBridgeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureImages();
  }

  void _ensureImages() {
    if (_images.isNotEmpty || _loading != null) return;
    if (_confirmedBridges().isEmpty) return;
    _loading = _loadImages();
  }

  /// Explicitly tagged bridge ways of the current snapshot.
  List<LineFeature> _confirmedBridges() {
    if (identical(_bridgeSource, widget.features)) return _bridgeLines;
    _bridgeSource = widget.features;
    _frameWater.clear();
    _frameEndpoints.clear();
    _placementKey = null;
    return _bridgeLines = List.unmodifiable([
      for (final line in widget.features.lines)
        if (line.metadata.hasConfirmedBridge && line.points.length >= 2) line,
    ]);
  }

  Future<void> _loadImages() async {
    try {
      final images = await Future.wait(_assets.map(_resolveImage));
      if (mounted) setState(() => _images = images);
    } catch (_) {
      // The painter has a geometric fallback for missing optional artwork.
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _resolveImage(String asset) =>
      MapVisualAssetWarmup.resolveImage(context, asset);

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final geometries = _geometriesFor(camera);
    if (geometries.isEmpty) return const SizedBox.expand();
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BridgePainter(
            offset: _offset,
            geometries: geometries,
            images: _images,
          ),
        ),
      ),
    );
  }

  /// Bridge sprites in pan-frame coordinates. Placement depends on which
  /// bridges and water polygons are in view, exactly as before; their
  /// projections are reused while the camera only pans.
  List<PixelBridgeGeometry> _geometriesFor(MapCamera camera) {
    final bridges = [
      for (final line in _confirmedBridges())
        if (MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds))
          line,
    ];
    if (bridges.isEmpty) return const [];
    final waterAreas = [
      for (final area in widget.features.areas)
        if (area.kind == MapFeatureKind.water &&
            MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds))
          area,
    ];
    final frame = _frame;
    if (frame == null || !frame.accepts(camera)) {
      _frame = PanProjectionFrame(camera);
      _frameWater.clear();
      _frameEndpoints.clear();
      _placementKey = null;
    }
    final offset = _offset = _frame!.offsetFor(camera);
    final placementKey = Object.hash(
      Object.hashAll(bridges),
      Object.hashAll(waterAreas),
    );
    if (placementKey == _placementKey) return _geometries;
    Offset project(LatLng point) =>
        PanProjectionFrame.project(camera, offset, point);
    final waterPolygons = [
      for (final area in waterAreas)
        _frameWater[area] ??= _BridgeWaterArea(
          polygon: OsmWaterPolygonProjector.project(area, project),
          holes: [
            for (final hole in area.holes)
              OsmWaterPolygonProjector.projectRing(hole, project),
          ],
        ),
    ].where((area) => area.polygon.length >= 3).toList(growable: false);
    final geometries = <PixelBridgeGeometry>[];
    for (final bridge in bridges) {
      var (start, end) = _frameEndpoints[bridge] ??= (
        project(bridge.points.first),
        project(bridge.points.last),
      );
      final crossingCenter = Offset.lerp(start, end, .5)!;
      final crossingDirection = end - start;
      PixelBridgePlacement? bestPlacement;
      for (final water in waterPolygons) {
        final placement = PixelBridgePlacement.fromWaterPolygon(
          polygon: water.polygon,
          holes: water.holes,
          center: crossingCenter,
          direction: crossingDirection,
          // The bridge way is finite. An infinite axis can cross an unrelated
          // pond elsewhere in the viewport and create a false bridge. Keep a
          // small tolerance for OSM endpoints placed just inside the banks.
          maximumAxisGap: crossingDirection.distance * .75 + 8,
        );
        if (placement == null) continue;
        if (bestPlacement == null ||
            placement.distanceTo(crossingCenter) <
                bestPlacement.distanceTo(crossingCenter)) {
          bestPlacement = placement;
        }
      }
      if (bestPlacement != null) {
        start = bestPlacement.start;
        end = bestPlacement.end;
      }
      // If water polygons are available, an explicit bridge that misses all
      // of them is not painted: its geometry would otherwise float on land.
      // In cells with only linear river data there is no polygon to anchor to,
      // so the original bridge way remains the safe visual fallback.
      if (waterPolygons.isNotEmpty && bestPlacement == null) continue;
      final geometry = PixelBridgeGeometry.fromProjected(
        start: start,
        end: end,
        zoom: camera.zoom,
      );
      if (geometry != null) geometries.add(geometry);
    }
    _placementKey = placementKey;
    return _geometries = List.unmodifiable(geometries);
  }
}

class _BridgePainter extends CustomPainter {
  const _BridgePainter({
    required this.offset,
    required this.geometries,
    required this.images,
  });

  /// Translation from the geometries' pan frame to the screen.
  final Offset offset;
  final List<PixelBridgeGeometry> geometries;
  final List<ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = PanProjectionFrame.viewportIn(size, offset);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final geometry in geometries) {
      final bounds = Rect.fromCenter(
        center: geometry.center,
        width: geometry.width,
        height: geometry.height,
      ).inflate(geometry.height);
      if (!bounds.overlaps(viewport)) continue;
      canvas.save();
      canvas.translate(geometry.center.dx, geometry.center.dy);
      canvas.rotate(geometry.angle);
      canvas.drawRect(
        Rect.fromLTWH(
          -geometry.width / 2 + 2,
          -geometry.height / 2 + 3,
          geometry.width,
          geometry.height,
        ),
        Paint()..color = const Color(0x66312624),
      );
      if (images.isEmpty) {
        canvas.drawRect(
          Rect.fromLTWH(
            -geometry.width / 2,
            -geometry.height / 2,
            geometry.width,
            geometry.height,
          ),
          Paint()..color = const Color(0xFF795333),
        );
        canvas.restore();
        continue;
      }
      _drawImage(
        canvas,
        images[0],
        Rect.fromCenter(
          center: Offset.zero,
          width: geometry.width,
          height: geometry.height,
        ),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawImage(Canvas canvas, ui.Image image, Rect target) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      target,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_BridgePainter oldDelegate) =>
      oldDelegate.offset != offset ||
      oldDelegate.geometries != geometries ||
      oldDelegate.images != images;
}

class _BridgeWaterArea {
  const _BridgeWaterArea({required this.polygon, required this.holes});

  final List<Offset> polygon;
  final List<List<Offset>> holes;
}
