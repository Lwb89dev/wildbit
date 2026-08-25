import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/entities/geo_bounds.dart';
import 'offline_tile_plan.dart';

typedef OfflineTileProgress = FutureOr<void> Function(int completed, int total);

enum OfflineTileSource {
  osm('osm', OfflineTileCache.osmTemplate),
  hiking('hiking', OfflineTileCache.hikingTemplate);

  const OfflineTileSource(this.directoryName, this.template);

  final String directoryName;
  final String template;
}

/// Small file-backed cache used by the offline region downloader. Files are
/// written atomically so an interrupted download is safe to resume.
class OfflineTileCache {
  factory OfflineTileCache({
    http.Client? client,
    Future<Directory> Function()? rootDirectory,
    int minZoom = OfflineTilePlan.defaultMinZoom,
    int maxZoom = OfflineTilePlan.defaultMaxZoom,
    int maxTiles = OfflineTilePlan.defaultMaxTiles,
  }) => OfflineTileCache._(
    client ?? http.Client(),
    rootDirectory,
    minZoom,
    maxZoom,
    maxTiles,
  );

  OfflineTileCache._(
    this._client,
    this._rootDirectory,
    this.minZoom,
    this.maxZoom,
    this.maxTiles,
  );

  static const osmTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const hikingTemplate =
      'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png';
  static const estimatedBytesPerTile = 24 * 1024;

  final http.Client _client;
  final Future<Directory> Function()? _rootDirectory;
  final int minZoom;
  final int maxZoom;
  final int maxTiles;

  Future<Directory> get rootDirectory => _root();

  int estimatedBytes(
    GeoBounds bounds, {
    int? requestedMinZoom,
    int? requestedMaxZoom,
  }) =>
      OfflineTilePlan.estimate(
        bounds,
        minZoom: requestedMinZoom ?? minZoom,
        maxZoom: requestedMaxZoom ?? maxZoom,
      ) *
      2 *
      estimatedBytesPerTile;

  Future<int> downloadBounds(
    GeoBounds bounds, {
    OfflineTileProgress? onProgress,
    int? requestedMinZoom,
    int? requestedMaxZoom,
  }) async {
    final effectiveMinZoom = requestedMinZoom ?? minZoom;
    final effectiveMaxZoom = requestedMaxZoom ?? maxZoom;
    final tiles = OfflineTilePlan.forBounds(
      bounds,
      minZoom: effectiveMinZoom,
      maxZoom: effectiveMaxZoom,
      maxTiles: maxTiles,
    );
    final sources = OfflineTileSource.values;
    final total = tiles.length * sources.length;
    var completed = 0;
    var downloaded = 0;
    final root = await _root();
    for (final tile in tiles) {
      for (final source in sources) {
        final file = File(
          path.join(
            root.path,
            'tiles',
            source.directoryName,
            '${tile.zoom}',
            '${tile.x}',
            '${tile.y}.png',
          ),
        );
        if (!await file.exists()) {
          final response = await _client
              .get(
                Uri.parse(OfflineTilePlan.url(source.template, tile)),
                headers: const {
                  'User-Agent':
                      'WildBit/1.0 (+https://wildbit.app) offline-hiking-app',
                },
              )
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            throw HttpException(
              'Tile ${source.directoryName}/${tile.key} HTTP ${response.statusCode}',
            );
          }
          await file.parent.create(recursive: true);
          final partial = File('${file.path}.part');
          await partial.writeAsBytes(response.bodyBytes, flush: true);
          await partial.rename(file.path);
          downloaded++;
        }
        completed++;
        await onProgress?.call(completed, total);
      }
    }
    return downloaded;
  }

  /// Returns the bytes currently occupied by complete and partial tile files.
  /// Directory metadata is intentionally excluded from the estimate.
  Future<int> cacheBytes() async {
    final root = await _root();
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        // A concurrent cleanup/download may remove the file between list and
        // stat; the remaining files still give a useful lower-bound estimate.
      }
    }
    return total;
  }

  /// Removes only interrupted atomic writes. Complete tiles are never
  /// deleted, so this cleanup cannot invalidate an offline region.
  Future<int> cleanupPartialFiles() async {
    final root = await _root();
    if (!await root.exists()) return 0;
    var removedBytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.part')) continue;
      try {
        removedBytes += await entity.length();
        await entity.delete();
      } on FileSystemException {
        // Ignore a file removed by a concurrent download retry.
      }
    }
    return removedBytes;
  }

  Future<Directory> _root() =>
      _rootDirectory?.call() ??
      getApplicationSupportDirectory().then(
        (directory) => Directory(path.join(directory.path, 'wildbit_offline')),
      );
}
