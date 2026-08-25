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
  OfflineTileCache({
    http.Client? client,
    Future<Directory> Function()? rootDirectory,
    this.minZoom = OfflineTilePlan.defaultMinZoom,
    this.maxZoom = OfflineTilePlan.defaultMaxZoom,
    this.maxTiles = OfflineTilePlan.defaultMaxTiles,
  })  : _client = client ?? http.Client(),
        _rootDirectory = rootDirectory;

  static const osmTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const hikingTemplate =
      'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png';
  static const estimatedBytesPerTile = 24 * 1024;

  final http.Client _client;
  final Future<Directory> Function()? _rootDirectory;
  final int minZoom;
  final int maxZoom;
  final int maxTiles;

  Future<Directory> get rootDirectory => _root();

  int estimatedBytes(GeoBounds bounds) =>
      OfflineTilePlan.estimate(
            bounds,
            minZoom: minZoom,
            maxZoom: maxZoom,
          ) *
      2 *
      estimatedBytesPerTile;

  Future<int> downloadBounds(
    GeoBounds bounds, {
    OfflineTileProgress? onProgress,
  }) async {
    final tiles = OfflineTilePlan.forBounds(
      bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxTiles: maxTiles,
    );
    final sources = OfflineTileSource.values;
    final total = tiles.length * sources.length;
    var completed = 0;
    var downloaded = 0;
    final root = await _root();
    for (final tile in tiles) {
      for (final source in sources) {
        final file = File(path.join(root.path, 'tiles', source.directoryName,
            '${tile.zoom}', '${tile.x}', '${tile.y}.png'));
        if (!await file.exists()) {
          final response = await _client
              .get(Uri.parse(OfflineTilePlan.url(source.template, tile)), headers: const {
                'User-Agent': 'WildBit/1.0 (+https://wildbit.app) offline-hiking-app',
              })
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

  Future<Directory> _root() => _rootDirectory?.call() ??
      getApplicationSupportDirectory().then(
        (directory) => Directory(path.join(directory.path, 'wildbit_offline')),
      );
}
