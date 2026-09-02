import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../assets/map_visual_asset_warmup.dart';

/// WildBit's screen-anchored pixel-art ground.
///
/// The authored grass tile is assembled once into a display-sized GPU image.
/// A repeated [DecorationImage] made the raster thread shade the full viewport
/// on physical Android devices. The precomposed image preserves nearest pixel
/// sampling while the live map composites one texture behind OSM geometry.
class PixelTerrainBaseLayer extends StatefulWidget {
  const PixelTerrainBaseLayer({super.key});

  @override
  State<PixelTerrainBaseLayer> createState() => _PixelTerrainBaseLayerState();
}

class _PixelTerrainBaseLayerState extends State<PixelTerrainBaseLayer> {
  ui.Image? _tile;
  ui.Image? _surface;
  _TerrainSurfaceKey? _surfaceKey;
  Future<void>? _composeTask;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTile();
  }

  void _loadTile() {
    if (_tile != null || _composeTask != null) return;
    _composeTask =
        MapVisualAssetWarmup.resolveImage(
              context,
              'assets/map/mock/terrain/grass_1.png',
            )
            .then((tile) {
              _tile = tile;
            })
            .whenComplete(() {
              _composeTask = null;
              if (mounted) setState(() {});
            });
  }

  void _ensureSurface(Size logicalSize, double devicePixelRatio) {
    final width = (logicalSize.width * devicePixelRatio).round();
    final height = (logicalSize.height * devicePixelRatio).round();
    if (width <= 0 || height <= 0) return;
    final key = _TerrainSurfaceKey(width, height);
    if (_surfaceKey == key || _composeTask != null) return;
    final tile = _tile;
    if (tile == null) {
      _loadTile();
      return;
    }
    _surfaceKey = key;
    final generation = ++_generation;
    _composeTask = _compose(tile, key)
        .then((surface) {
          if (!mounted || generation != _generation) {
            surface.dispose();
            return;
          }
          final previous = _surface;
          setState(() => _surface = surface);
          previous?.dispose();
        })
        .catchError((_) {
          // The flat semantic fallback remains available if allocation fails.
          if (generation == _generation) _surfaceKey = null;
        })
        .whenComplete(() {
          _composeTask = null;
          if (mounted) setState(() {});
        });
  }

  Future<ui.Image> _compose(ui.Image tile, _TerrainSurfaceKey key) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (var y = 0; y < key.height; y += tile.height) {
      for (var x = 0; x < key.width; x += tile.width) {
        canvas.drawImage(tile, Offset(x.toDouble(), y.toDouble()), paint);
      }
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(key.width, key.height);
    } finally {
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _surface?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      _ensureSurface(size, MediaQuery.devicePixelRatioOf(context));
      final surface = _surface;
      return RepaintBoundary(
        child: IgnorePointer(
          child: surface == null
              ? const ColoredBox(color: Color(0xFF688B42))
              : RawImage(
                  image: surface,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
        ),
      );
    },
  );
}

class _TerrainSurfaceKey {
  const _TerrainSurfaceKey(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _TerrainSurfaceKey &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
