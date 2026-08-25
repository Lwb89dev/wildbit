import 'dart:math' as math;

import '../domain/entities/geo_bounds.dart';

/// A single slippy-map tile selected for an offline region.
class OfflineTileCoordinate {
  const OfflineTileCoordinate({
    required this.zoom,
    required this.x,
    required this.y,
  });

  final int zoom;
  final int x;
  final int y;

  String get key => '$zoom/$x/$y';
}

/// Deterministic tile selection shared by the offline downloader and UI.
/// Keeping this independent of flutter_map makes the requested area testable
/// without a map widget or network connection.
abstract final class OfflineTilePlan {
  static const defaultMinZoom = 12;
  static const defaultMaxZoom = 15;
  static const defaultMaxTiles = 320;

  static List<OfflineTileCoordinate> forBounds(
    GeoBounds bounds, {
    int minZoom = defaultMinZoom,
    int maxZoom = defaultMaxZoom,
    int maxTiles = defaultMaxTiles,
  }) {
    if (minZoom < 0 || maxZoom < minZoom) {
      throw ArgumentError('Invalid offline tile zoom range');
    }
    if (maxTiles <= 0) throw ArgumentError.value(maxTiles, 'maxTiles');

    final tiles = <OfflineTileCoordinate>[];
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final scale = 1 << zoom;
      final west = _x(bounds.southWest.longitude, zoom);
      final east = _x(bounds.northEast.longitude, zoom);
      final north = _y(bounds.northEast.latitude, zoom);
      final south = _y(bounds.southWest.latitude, zoom);
      final xRanges = west <= east
          ? [(west, east)]
          : [(west, scale - 1), (0, east)];
      for (final (startX, endX) in xRanges) {
        for (var x = startX; x <= endX; x++) {
          for (var y = north; y <= south; y++) {
            tiles.add(OfflineTileCoordinate(zoom: zoom, x: x, y: y));
            if (tiles.length > maxTiles) {
              throw StateError(
                'Area troppo grande: riduci lo zoom o la selezione '
                '(massimo $maxTiles tile)',
              );
            }
          }
        }
      }
    }
    return tiles;
  }

  static int _x(double longitude, int zoom) {
    final normalized = (longitude + 180) / 360;
    return (normalized * (1 << zoom)).floor().clamp(0, (1 << zoom) - 1);
  }

  static int _y(double latitude, int zoom) {
    final clamped = latitude.clamp(-85.05112878, 85.05112878);
    final radians = clamped * math.pi / 180;
    final projected =
        (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
            2;
    return (projected * (1 << zoom)).floor().clamp(0, (1 << zoom) - 1);
  }

  static String url(String template, OfflineTileCoordinate tile) => template
      .replaceAll('{z}', '${tile.zoom}')
      .replaceAll('{x}', '${tile.x}')
      .replaceAll('{y}', '${tile.y}');

  // Exposed for UI estimates and tests without requiring a full tile list.
  static int estimate(GeoBounds bounds, {int minZoom = defaultMinZoom, int maxZoom = defaultMaxZoom}) {
    return forBounds(
      bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxTiles: 1 << 30,
    ).length;
  }
}
