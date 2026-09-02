import 'dart:async';

import '../data/osm/map_cell_grid.dart';
import '../data/repositories/osm_map_data_repository.dart';
import '../domain/entities/geo_bounds.dart';
import '../domain/entities/offline_region.dart';
import '../domain/enums/offline_area_status.dart';
import '../domain/repositories/offline_region_repository.dart';
import 'offline_tile_cache.dart';
import 'offline_tile_plan.dart';

/// Downloads every OSM grid cell covering an area and marks it available
/// offline. Resuming after an interrupted download is "free": cells already
/// cached by [OsmMapDataRepository] are skipped on the next attempt instead
/// of being re-fetched.
class OfflineDownloadManager {
  factory OfflineDownloadManager({
    required OfflineRegionRepository areaRepository,
    required OsmMapDataRepository mapDataRepository,
    OfflineTileCache? tileCache,
  }) => OfflineDownloadManager._(
    areaRepository,
    mapDataRepository,
    tileCache ?? OfflineTileCache(),
  );

  OfflineDownloadManager._(
    this._areaRepository,
    this._mapDataRepository,
    this._tileCache,
  );

  final OfflineRegionRepository _areaRepository;
  final OsmMapDataRepository _mapDataRepository;
  final OfflineTileCache _tileCache;

  Future<int> requestDownload({
    required String name,
    required GeoBounds bounds,
    int? minZoom,
    int? maxZoom,
  }) async {
    final effectiveMinZoom = minZoom ?? _tileCache.minZoom;
    final effectiveMaxZoom = maxZoom ?? _tileCache.maxZoom;
    final id = await _areaRepository.create(
      OfflineRegion(
        name: name,
        bounds: bounds,
        status: OfflineAreaStatus.queued,
        progress: 0,
        requestedAt: DateTime.now(),
        minZoom: effectiveMinZoom,
        maxZoom: effectiveMaxZoom,
      ),
    );
    unawaited(
      _run(id, bounds, minZoom: effectiveMinZoom, maxZoom: effectiveMaxZoom),
    );
    return id;
  }

  Future<void> _run(
    int id,
    GeoBounds bounds, {
    required int minZoom,
    required int maxZoom,
  }) async {
    await _areaRepository.updateStatus(
      id,
      status: OfflineAreaStatus.downloading,
      progress: 0,
    );

    final cells = MapCellGrid.cellsCovering(bounds);
    try {
      for (final (index, cell) in cells.indexed) {
        await _mapDataRepository.loadFeatures(cell);
        await _areaRepository.updateStatus(
          id,
          status: OfflineAreaStatus.downloading,
          // OSM feature cells are the first half; raster map + hiking overlay
          // tiles are downloaded in the second half below.
          progress: cells.isEmpty ? .5 : (index + 1) / cells.length * .5,
        );
      }
      await _tileCache.downloadBounds(
        bounds,
        requestedMinZoom: minZoom,
        requestedMaxZoom: maxZoom,
        onProgress: (completed, total) async {
          await _areaRepository.updateStatus(
            id,
            status: OfflineAreaStatus.downloading,
            progress: .5 + (total == 0 ? .5 : completed / total * .5),
          );
        },
      );
      await _areaRepository.updateStatus(
        id,
        status: OfflineAreaStatus.completed,
        progress: 1,
      );
    } catch (_) {
      await _areaRepository.updateStatus(id, status: OfflineAreaStatus.failed);
    }
  }

  /// Retries a previously failed/interrupted download from where it left
  /// off (already-cached cells are skipped by the repository itself).
  Future<void> retry(OfflineRegion area) =>
      _run(area.id!, area.bounds, minZoom: area.minZoom, maxZoom: area.maxZoom);

  /// Frees an area's private raster tiles while retaining any tile selected by
  /// another offline area. Downloads in progress are intentionally not
  /// removable from the UI: a network response racing deletion could otherwise
  /// recreate a file after it has been accounted as freed.
  Future<int> delete(OfflineRegion area) async {
    final id = area.id;
    if (id == null) return 0;
    final retained = <String>{};
    final areas = await _areaRepository.listAreas();
    for (final other in areas) {
      if (other.id == id) continue;
      retained.addAll(
        OfflineTilePlan.forBounds(
          other.bounds,
          minZoom: other.minZoom,
          maxZoom: other.maxZoom,
          maxTiles: _tileCache.maxTiles,
        ).map((tile) => tile.key),
      );
    }
    final removed = await _tileCache.removeBounds(
      area.bounds,
      requestedMinZoom: area.minZoom,
      requestedMaxZoom: area.maxZoom,
      retainedKeys: retained,
    );
    await _areaRepository.deleteArea(id);
    return removed;
  }
}
