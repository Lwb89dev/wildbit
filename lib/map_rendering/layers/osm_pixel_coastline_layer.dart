import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../composition/coastline_topology_composer.dart';
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
  State<OsmPixelCoastlineLayer> createState() =>
      _OsmPixelCoastlineLayerState();
}

class _OsmPixelCoastlineLayerState extends State<OsmPixelCoastlineLayer> {
  static const _asset = 'assets/map/mock/terrain/water_flow.png';

  ui.Image? _image;
  Future<void>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_image == null) _loading ??= _loadImage();
  }

  Future<void> _loadImage() async {
    final completer = Completer<ui.Image>();
    final stream = const AssetImage(_asset).resolve(
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
      if (mounted) setState(() => _image = image);
    } catch (_) {
      // A solid sea fill remains available when optional artwork is missing.
    } finally {
      _loading = null;
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CoastlinePainter(
              camera: MapCamera.of(context),
              topology: widget.topology,
              image: _image,
            ),
          ),
        ),
      );
}

class _CoastlinePainter extends CustomPainter {
  const _CoastlinePainter({
    required this.camera,
    required this.topology,
    required this.image,
  });

  final MapCamera camera;
  final CoastlineTopology topology;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || topology.chains.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFF3987A3)
      ..filterQuality = FilterQuality.none;
    if (image != null) {
      paint.shader = ui.ImageShader(
        image!,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Float64List.fromList(const [
          1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        ]),
        filterQuality: ui.FilterQuality.none,
      );
    }

    final closedWater = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    var hasClosedRing = false;
    final closedEdges = <Path>[];
    for (final chain in topology.chains.where((chain) => chain.isClosed)) {
      if (chain.points.length < 3) continue;
      final projected = [
        for (final point in chain.points) camera.latLngToScreenOffset(point),
      ];
      closedWater.addPolygon(projected, true);
      closedEdges.add(Path()..addPolygon(projected, true));
      hasClosedRing = true;
    }
    if (hasClosedRing) canvas.drawPath(closedWater, paint);

    final openEdges = <Path>[];
    for (final chain in topology.chains.where((chain) => !chain.isClosed)) {
      if (chain.points.length < 2) continue;
      final points = [
        for (final point in chain.points) camera.latLngToScreenOffset(point),
      ];
      final firstDelta = points[1] - points.first;
      final lastDelta = points.last - points[points.length - 2];
      final extent = size.longestSide * 3;
      final firstRight = _rightNormal(firstDelta) * extent;
      final lastRight = _rightNormal(lastDelta) * extent;
      final coastEdge = Path()..addPolygon(points, false);
      openEdges.add(coastEdge);
      canvas.drawPath(
        Path()..addPolygon([
          ...points,
          points.last + lastRight,
          points.first + firstRight,
        ], true),
        paint,
      );
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

  @override
  bool shouldRepaint(_CoastlinePainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.topology != topology ||
      oldDelegate.image != image;
}
