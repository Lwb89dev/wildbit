import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as path;

import 'offline_tile_cache.dart';
import 'offline_tile_plan.dart';

/// Reads a pre-downloaded tile from the WildBit cache and falls back to the
/// public endpoint when the user is browsing an area that is not cached yet.
class OfflineTileProvider extends TileProvider {
  OfflineTileProvider({
    required this.source,
    required this.cacheDirectory,
  });

  final OfflineTileSource source;
  final String cacheDirectory;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final tile = OfflineTileCoordinate(
      zoom: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
    final file = File(path.join(
      cacheDirectory,
      'tiles',
      source.directoryName,
      '${tile.zoom}',
      '${tile.x}',
      '${tile.y}.png',
    ));
    if (file.existsSync()) return FileImage(file);
    return NetworkImage(
      OfflineTilePlan.url(source.template, tile),
      headers: const {
        'User-Agent': 'WildBit/1.0 (+https://wildbit.app) offline-hiking-app',
      },
    );
  }
}
