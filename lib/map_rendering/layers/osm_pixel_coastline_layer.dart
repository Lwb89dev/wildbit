import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../assets/map_visual_asset_warmup.dart';
import '../composition/coastline_topology_composer.dart';
import '../composition/coastline_ring_classifier.dart';
import '../performance/map_rendering_budget.dart';

/// Fills the water side of directed OSM coastlines in a single Canvas pass.
///
/// OSM coastlines place land on the left and water on the right. Closed rings
/// are treated as islands through an even-odd fill; open chains are extended
/// only toward their mathematically defined right side. This is visual-only
/// and never changes route or download geometry.
class OsmPixelCoastlineLayer extends StatefulWidget {
  const OsmPixelCoastlineLayer({super.key, required this.topology});

  final CoastlineTopology topology;

  @override
  State<OsmPixelCoastlineLayer> createState() => _OsmPixelCoastlineLayerState();
}

class _OsmPixelCoastlineLayerState extends State<OsmPixelCoastlineLayer> {
  static const _asset = 'assets/map/mock/terrain/water_flow.png';

  ui.Image? _image;
  ui.Shader? _shader;
  Future<void>? _loading;
  _CoastlineViewKey? _painterViewKey;
  _CoastlinePainter? _cachedPainter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureImage();
  }

  @override
  void didUpdateWidget(covariant OsmPixelCoastlineLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.topology, widget.topology)) {
      _painterViewKey = null;
      _cachedPainter = null;
    }
    _ensureImage();
  }

  void _ensureImage() {
    if (widget.topology.chains.isEmpty) return;
    if (_image == null) _loading ??= _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final image = await MapVisualAssetWarmup.resolveImage(context, _asset);
      if (mounted) {
        setState(() {
          _image = image;
          _shader = _shaderFor(image);
        });
      }
    } catch (_) {
      // A solid sea fill remains available when optional artwork is missing.
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
    if (widget.topology.chains.isEmpty) return const SizedBox.expand();
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _buildPainter(MapCamera.of(context)),
        ),
      ),
    );
  }

  _CoastlinePainter _buildPainter(MapCamera camera) {
    // A location tick, Bit frame or controls rebuild must not reproject every
    // coastline way when the camera itself has not changed. The key is exact:
    // it intentionally does not quantise centre, zoom or rotation, so a
    // coastline can never be painted at a stale geographic position.
    final viewKey = _CoastlineViewKey(
      topology: widget.topology,
      shader: _shader,
      centerLatitude: camera.center.latitude,
      centerLongitude: camera.center.longitude,
      zoom: camera.zoom,
      rotation: camera.rotation,
      width: camera.nonRotatedSize.width,
      height: camera.nonRotatedSize.height,
    );
    final cached = _cachedPainter;
    if (cached != null && _painterViewKey == viewKey) return cached;
    final closed = [
      for (final chain in widget.topology.chains.where(
        (chain) => chain.isClosed,
      ))
        if (chain.points.length >= 3)
          _CoastlineProjection.projectWrapped(chain.points, camera),
    ];
    final open = [
      for (final chain in widget.topology.chains.where(
        (chain) => !chain.isClosed,
      ))
        if (chain.points.length >= 2)
          _CoastlineProjection.projectWrapped(chain.points, camera),
    ];
    final painter = _CoastlinePainter(
      camera: camera,
      closedRings: CoastlineRingClassifier.classify(closed),
      openChains: List.unmodifiable(open),
      shader: _shader,
    );
    _painterViewKey = viewKey;
    _cachedPainter = painter;
    return painter;
  }
}

/// Exact paint-space key. Geographic coastlines are allowed to cross the
/// antimeridian, therefore rounded camera values would be unsafe here.
class _CoastlineViewKey {
  const _CoastlineViewKey({
    required this.topology,
    required this.shader,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.zoom,
    required this.rotation,
    required this.width,
    required this.height,
  });

  final CoastlineTopology topology;
  final ui.Shader? shader;
  final double centerLatitude;
  final double centerLongitude;
  final double zoom;
  final double rotation;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is _CoastlineViewKey &&
      identical(other.topology, topology) &&
      identical(other.shader, shader) &&
      other.centerLatitude == centerLatitude &&
      other.centerLongitude == centerLongitude &&
      other.zoom == zoom &&
      other.rotation == rotation &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(
    identityHashCode(topology),
    identityHashCode(shader),
    centerLatitude,
    centerLongitude,
    zoom,
    rotation,
    width,
    height,
  );
}

class _CoastlinePainter extends CustomPainter {
  const _CoastlinePainter({
    required this.camera,
    required this.closedRings,
    required this.openChains,
    required this.shader,
  });

  final MapCamera camera;
  final List<CoastlineRing> closedRings;
  final List<List<Offset>> openChains;
  final ui.Shader? shader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || (closedRings.isEmpty && openChains.isEmpty)) return;
    final paint = Paint()
      ..color = const Color(0xFF3987A3)
      ..filterQuality = FilterQuality.none;
    if (shader != null) paint.shader = shader;

    final closedWater = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    var hasClosedRing = false;
    final closedEdges = <Path>[];
    for (final ring in closedRings) {
      closedWater.addPolygon(ring.points, true);
      closedEdges.add(Path()..addPolygon(ring.points, true));
      hasClosedRing = true;
    }
    if (hasClosedRing) canvas.drawPath(closedWater, paint);

    final openEdges = <Path>[];
    for (final points in openChains) {
      final extent = size.longestSide * 3;
      final coastEdge = Path()..addPolygon(points, false);
      openEdges.add(coastEdge);
      canvas.drawPath(_openWaterPolygon(points, extent), paint);
    }
    for (final edge in [...closedEdges, ...openEdges]) {
      _paintCoastEdge(canvas, edge);
    }
  }

  void _paintCoastEdge(Canvas canvas, Path edge) {
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      referenceZoom: 15,
      min: .45,
      max: 1.1,
    );
    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xFF3D4938)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * scale
        ..strokeJoin = StrokeJoin.bevel
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
    canvas.drawPath(
      edge,
      Paint()
        // Coastline topology alone does not prove a beach. Use a neutral
        // stone/earth bank instead of falsely depicting sand everywhere.
        ..color = const Color(0xFF80796D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2 * scale
        ..strokeJoin = StrokeJoin.bevel
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xFFD1EFEB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 1.4 * scale)
        ..strokeJoin = StrokeJoin.bevel
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
  }

  Offset _rightNormal(Offset delta) {
    final length = delta.distance;
    if (length == 0) return Offset.zero;
    return Offset(delta.dy / length, -delta.dx / length);
  }

  /// Builds the water-side half-plane for an open coastline chain.
  ///
  /// A single offset at each endpoint works for a straight coast but folds
  /// into the land side as soon as the chain bends. Offsetting every vertex
  /// from its local tangent keeps the sea on OSM's directed right side around
  /// bays, headlands, and viewport-clipped island fragments.
  Path _openWaterPolygon(List<Offset> coast, double extent) {
    final offset = <Offset>[];
    for (var i = 0; i < coast.length; i++) {
      final tangent = i == 0
          ? coast[1] - coast[0]
          : i == coast.length - 1
          ? coast[i] - coast[i - 1]
          : coast[i + 1] - coast[i - 1];
      offset.add(coast[i] + _rightNormal(tangent) * extent);
    }
    return Path()..addPolygon([...coast, ...offset.reversed], true);
  }

  @override
  bool shouldRepaint(_CoastlinePainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.closedRings != closedRings ||
      oldDelegate.openChains != openChains ||
      oldDelegate.shader != shader;
}

abstract final class _CoastlineProjection {
  /// Projects a geographic chain into the world nearest the camera.
  /// Coastlines crossing 180°E/180°W are unwrapped before rotation, matching
  /// flutter_map's world projection and avoiding a false line across the map.
  static List<Offset> projectWrapped(List<LatLng> points, MapCamera camera) {
    if (points.isEmpty) return const [];
    final worldWidth = camera.getWorldWidthAtZoom(camera.zoom);
    final mapCenter = camera.crs.latLngToOffset(camera.center, camera.zoom);
    final origin = mapCenter - camera.nonRotatedSize.center(Offset.zero);
    final unwrapped = <Offset>[];
    var previousX = mapCenter.dx;
    for (final point in points) {
      final raw = camera.crs.latLngToOffset(point, camera.zoom);
      var x = raw.dx;
      if (worldWidth > 0) {
        while (x - previousX > worldWidth / 2) {
          x -= worldWidth;
        }
        while (x - previousX < -worldWidth / 2) {
          x += worldWidth;
        }
      }
      previousX = x;
      var projected = Offset(x, raw.dy);
      if (camera.rotation != 0) {
        projected = camera.rotatePoint(
          mapCenter,
          projected,
          counterRotation: false,
        );
      }
      unwrapped.add(projected - origin);
    }
    final tolerance = (8 - camera.zoom * .25).clamp(1.2, 4.0).toDouble();
    return decimate(unwrapped, tolerance);
  }

  static List<Offset> decimate(List<Offset> points, double tolerance) {
    if (points.length < 3) return points;
    final squaredTolerance = tolerance * tolerance;
    final result = <Offset>[points.first];
    var previous = points.first;
    for (final point in points.skip(1).take(points.length - 2)) {
      final dx = point.dx - previous.dx;
      final dy = point.dy - previous.dy;
      if (dx * dx + dy * dy < squaredTolerance) continue;
      result.add(point);
      previous = point;
    }
    result.add(points.last);
    return result;
  }
}
