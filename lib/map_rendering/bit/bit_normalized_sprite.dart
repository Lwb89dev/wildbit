import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bit_frame_metrics.dart';
import 'bit_motion_state.dart';

/// Draws a Bit frame using its alpha bounds rather than its transparent
/// source canvas. The authored frames are all 100×150, but the opaque pose
/// moves inside that canvas; mapping the alpha rectangle to one fixed target
/// rectangle prevents visible size and baseline pulsing between frames.
class BitNormalizedSprite extends StatefulWidget {
  const BitNormalizedSprite({
    super.key,
    required this.assetPath,
    required this.state,
    required this.frameIndex,
    required this.width,
    required this.height,
  });

  final String assetPath;
  final BitMotionState state;
  final int frameIndex;
  final double width;
  final double height;

  @override
  State<BitNormalizedSprite> createState() => _BitNormalizedSpriteState();
}

class _BitNormalizedSpriteState extends State<BitNormalizedSprite> {
  static final Map<String, ui.Image> _sharedImages = <String, ui.Image>{};
  static final Map<String, Future<ui.Image>> _sharedLoads =
      <String, Future<ui.Image>>{};

  final Map<String, ui.Image> _images = <String, ui.Image>{};
  final Set<String> _loadingAssets = <String>{};
  ui.Image? _lastImage;
  BitFrameMetrics? _lastMetrics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant BitNormalizedSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) _loadIfNeeded();
  }

  void _loadIfNeeded() {
    final asset = widget.assetPath;
    if (_images.containsKey(asset) || !_loadingAssets.add(asset)) return;
    final shared = _sharedImages[asset];
    if (shared != null) {
      _images[asset] = shared;
      _loadingAssets.remove(asset);
      return;
    }
    _load(asset);
  }

  Future<void> _load(String asset) async {
    try {
      final image = await (_sharedLoads[asset] ??= _resolveImage(asset));
      _sharedImages[asset] = image;
      if (mounted) {
        setState(() {
          _images[asset] = image;
        });
      }
    } catch (_) {
      // Keep the previous frame while an optional sprite is unavailable.
    } finally {
      _loadingAssets.remove(asset);
      if (mounted) _loadIfNeeded();
    }
  }

  Future<ui.Image> _resolveImage(String asset) {
    final completer = Completer<ui.Image>();
    final stream = AssetImage(
      asset,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image);
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
    _loadIfNeeded();
    final currentMetrics = BitFrameMetrics.forFrame(
      widget.state,
      widget.frameIndex,
    );
    final currentImage = _images[widget.assetPath];
    final image = currentImage ?? _lastImage;
    final metrics = currentImage == null ? _lastMetrics : currentMetrics;
    if (image == null || metrics == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    _lastImage = image;
    _lastMetrics = metrics;
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _BitNormalizedPainter(
        image: image,
        metrics: metrics,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
    );
  }
}

class _BitNormalizedPainter extends CustomPainter {
  const _BitNormalizedPainter({
    required this.image,
    required this.metrics,
    required this.devicePixelRatio,
  });

  final ui.Image image;
  final BitFrameMetrics metrics;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image.width == 0 || image.height == 0) return;
    // Snap the common destination footprint to physical pixels once. Without
    // this, a 22.8 logical-pixel sprite can be rasterised as 22 or 23 pixels
    // depending on the source crop of the current frame.
    double snap(double value) =>
        (value * devicePixelRatio).round() / devicePixelRatio;

    final visualHeight = snap(
      size.height * BitFrameMetrics.targetVisualHeight / 150,
    );
    // Crop to the measured opaque bounds before scaling. The same uniform
    // scale is used on both axes: independently forcing every frame to the
    // same width makes the narrow map-pull frames visibly stretch sideways.
    // The body therefore keeps its proportions; the map/arms may occupy a
    // naturally different amount of space as the pose changes.
    final source = Rect.fromLTWH(
      metrics.contentLeft,
      metrics.contentTop,
      metrics.contentWidth,
      metrics.contentHeight,
    );
    final uniformScale = visualHeight / metrics.contentHeight;
    final renderedWidth = snap(metrics.contentWidth * uniformScale);
    // Keep the feet on the widget's fixed centre. Centering the changing
    // alpha bounds instead makes Bit slide sideways whenever the map opens.
    final pivotOffset = (metrics.anchorX - metrics.contentLeft) * uniformScale;
    final left = snap(size.width / 2 - pivotOffset);
    final top = snap(size.height - visualHeight);
    final destination = Rect.fromLTWH(left, top, renderedWidth, visualHeight);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    canvas.drawImageRect(image, source, destination, paint);
  }

  @override
  bool shouldRepaint(_BitNormalizedPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.metrics != metrics ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
