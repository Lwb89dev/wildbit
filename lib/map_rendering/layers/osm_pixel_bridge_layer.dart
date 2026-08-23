import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../composition/pixel_bridge_geometry.dart';
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
    'assets/map/mock/structures/bridge_foot_start.png',
    'assets/map/mock/structures/bridge_foot_mid.png',
    'assets/map/mock/structures/bridge_foot_end.png',
  ];

  List<ui.Image> _images = const [];
  Future<void>? _loading;

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
      // The painter has a geometric fallback for missing optional artwork.
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
  Widget build(BuildContext context) => RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _BridgePainter(
              camera: MapCamera.of(context),
              features: widget.features,
              images: _images,
            ),
          ),
        ),
      );
}

class _BridgePainter extends CustomPainter {
  const _BridgePainter({
    required this.camera,
    required this.features,
    required this.images,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final List<ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    final bridges = features.lines.where(
      (line) =>
          line.metadata.hasConfirmedBridge &&
          line.points.length >= 2 &&
          MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds),
    );
    for (final bridge in bridges) {
      final geometry = PixelBridgeGeometry.fromProjected(
        start: camera.latLngToScreenOffset(bridge.points.first),
        end: camera.latLngToScreenOffset(bridge.points.last),
        zoom: camera.zoom,
      );
      if (geometry == null) continue;
      final bounds = Rect.fromCenter(
        center: geometry.center,
        width: geometry.width,
        height: geometry.height,
      ).inflate(geometry.height);
      if (!bounds.overlaps(Offset.zero & size)) continue;
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
      if (images.length < 3) {
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
      final left = -geometry.width / 2;
      _drawImage(
        canvas,
        images[0],
        Rect.fromLTWH(
          left,
          -geometry.height / 2,
          geometry.capWidth,
          geometry.height,
        ),
      );
      final middleWidth = geometry.width - geometry.capWidth * 2;
      final segmentWidth = middleWidth / geometry.midSegments;
      for (var index = 0; index < geometry.midSegments; index++) {
        _drawImage(
          canvas,
          images[1],
          Rect.fromLTWH(
            left + geometry.capWidth + index * segmentWidth,
            -geometry.height / 2,
            segmentWidth,
            geometry.height,
          ),
        );
      }
      _drawImage(
        canvas,
        images[2],
        Rect.fromLTWH(
          geometry.width / 2 - geometry.capWidth,
          -geometry.height / 2,
          geometry.capWidth,
          geometry.height,
        ),
      );
      canvas.restore();
    }
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
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.features != features ||
      oldDelegate.images != images;
}
