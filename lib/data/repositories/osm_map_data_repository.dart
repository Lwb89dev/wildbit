import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/repositories/map_data_repository.dart';
import '../../storage/database.dart';
import '../osm/feature_cache_codec.dart';
import '../osm/map_cell_grid.dart';
import '../osm/overpass_endpoints.dart';
import '../osm/overpass_parser.dart';
import '../osm/overpass_query_builder.dart';
import '../test_data/test_region.dart';
import '../test_data/mixed_preview_region.dart';

typedef MapCellLoaded =
    void Function(GeoBounds cell, MapFeatureCollection features);

/// Real map data: fetches OSM data per grid cell from the Overpass API and
/// caches every cell locally. Offline-first — if a fetch fails, whatever is
/// already cached for that cell is used instead of surfacing an error, so a
/// missing connection degrades to "possibly stale" rather than "broken".
class OsmMapDataRepository implements MapDataRepository {
  OsmMapDataRepository({
    required this._database,
    http.Client? httpClient,
    this.offlinePreview = false,
    this.mixedPreview = false,
  }) : _httpClient = httpClient ?? http.Client();

  final bool offlinePreview;
  final bool mixedPreview;

  static const _maxCacheAge = Duration(days: 30);
  static const _maxResponseBytes = 25 * 1024 * 1024;

  /// Bounds any single [loadFeatures] call to a sane number of Overpass
  /// requests, regardless of how large a [GeoBounds] a caller passes in —
  /// a bug (or a future caller) requesting a huge area must not turn into
  /// hundreds of concurrent requests against a shared public API.
  // A public Overpass instance is shared infrastructure. Fetch only the
  // nearest cells per viewport and do it serially; launching one request per
  // grid cell made a normal phone viewport look like a denial-of-service and
  // produced cascades of 502 responses.
  static const _maxCellsPerRequest = 4;

  final WildBitDatabase _database;
  final http.Client _httpClient;
  final Map<String, Future<_CellLoadResult>> _activeCellLoads = {};
  final Map<String, _MemoryCell> _memoryCells = {};
  final Set<String> _optionalContextKeys = {};
  Future<void> _optionalContextQueue = Future<void>.value();
  final _endpoints = OverpassEndpoints.instance;

  /// Read by the presentation layer after [loadFeatures]. Cached data remains
  /// usable offline; this is only set when a cell without cache cannot reach
  /// any configured Overpass endpoint.
  Object? lastLoadError;

  @override
  Future<MapFeatureCollection> loadFeatures(
    GeoBounds bounds, {
    MapCellLoaded? onCellLoaded,
  }) async {
    // mixedPreview is a variant of offlinePreview, not an independent mode —
    // requesting it implies offlinePreview even if the caller didn't also
    // set that flag.
    if (offlinePreview || mixedPreview) {
      lastLoadError = null;
      final features = mixedPreview ? mixedPreviewFeatures : testRegionFeatures;
      for (final cell in MapCellGrid.cellsCovering(bounds)) {
        onCellLoaded?.call(cell, features);
      }
      return features;
    }
    return _loadFeaturesInternal(bounds, onCellLoaded: onCellLoaded);
  }

  Future<MapFeatureCollection> _loadFeaturesInternal(
    GeoBounds bounds, {
    MapCellLoaded? onCellLoaded,
  }) async {
    lastLoadError = null;
    final cells = MapCellGrid.cellsCoveringNearestFirst(
      bounds,
    ).take(_maxCellsPerRequest);
    final collections = <MapFeatureCollection>[];
    final optionalContext = <_OptionalContextLoad>[];
    for (final cell in cells) {
      final result = await _loadCellShared(cell);
      if (!result.available) continue;
      collections.add(result.features);
      onCellLoaded?.call(cell, result.features);
      if (result.needsOptionalContext) {
        optionalContext.add(
          _OptionalContextLoad(
            cell: cell,
            key: MapCellGrid.keyFor(cell),
            base: result.features,
          ),
        );
      }
    }

    // Buildings and individual trees are useful context, but base geography
    // for every visible cell has priority. Starting these requests only after
    // the loop prevents an optional query from delaying the user's own cell.
    for (final context in optionalContext) {
      _scheduleOptionalContext(
        context.cell,
        context.key,
        context.base,
        onCellLoaded,
      );
    }

    return MapFeatureCollection(
      areas: [for (final c in collections) ...c.areas],
      lines: [for (final c in collections) ...c.lines],
      pois: [for (final c in collections) ...c.pois],
    ).deduplicated();
  }

  Future<_CellLoadResult> _loadCellShared(GeoBounds cell) async {
    final key = MapCellGrid.keyFor(cell);
    final active = _activeCellLoads[key];
    if (active != null) return active;
    final operation = _loadCell(cell, key);
    _activeCellLoads[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_activeCellLoads[key], operation)) {
        _activeCellLoads.remove(key);
      }
    }
  }

  Future<_CellLoadResult> _loadCell(GeoBounds cell, String key) async {
    final memory = _memoryCells[key];
    if (memory != null &&
        DateTime.now().difference(memory.fetchedAt) < _maxCacheAge) {
      return _CellLoadResult.available(memory.features);
    }
    final cached = await (_database.select(
      _database.cachedMapCells,
    )..where((t) => t.cellKey.equals(key))).getSingleOrNull();

    final isFresh =
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _maxCacheAge &&
        FeatureCacheCodec.isCurrentFormat(cached.featuresJson);
    if (isFresh) {
      final decoded = await compute(_decodeFeatureCache, cached.featuresJson);
      _memoryCells[key] = _MemoryCell(cached.fetchedAt, decoded);
      return _CellLoadResult.available(decoded);
    }

    // Show stale map data immediately while the semantic OSM refresh runs in
    // the background. A slow/temporarily unavailable Overpass endpoint must
    // never leave the map blank for minutes when a previous cell is usable.
    if (cached != null &&
        FeatureCacheCodec.isCurrentFormat(cached.featuresJson)) {
      final stale = await compute(_decodeFeatureCache, cached.featuresJson);
      // Treat stale disk data as session-fresh while one background refresh
      // runs, otherwise every camera/GPS callback starts another refresh.
      _memoryCells[key] = _MemoryCell(DateTime.now(), stale);
      unawaited(_refreshCell(cell, key));
      return _CellLoadResult.available(stale);
    }

    try {
      final fetched = await _fetchBaseFromOverpass(cell);
      _memoryCells[key] = _MemoryCell(DateTime.now(), fetched);
      // Rendering must not wait for JSON encoding and SQLite persistence.
      // The cell is already valid at this point; cache it in the background.
      unawaited(
        _storeCell(key, fetched).catchError((Object error) {
          debugPrint('WildBit OSM: cache cella $key fallita: $error');
        }),
      );
      return _CellLoadResult.available(fetched, needsOptionalContext: true);
    } catch (error) {
      lastLoadError ??= error;
      return const _CellLoadResult.unavailable();
    }
  }

  Future<void> _refreshCell(GeoBounds cell, String key) async {
    try {
      final base = await _fetchBaseFromOverpass(cell);
      _memoryCells[key] = _MemoryCell(DateTime.now(), base);
      await _storeCell(key, base);
      _scheduleOptionalContext(cell, key, base, null);
    } catch (error) {
      lastLoadError ??= error;
    }
  }

  void _scheduleOptionalContext(
    GeoBounds cell,
    String key,
    MapFeatureCollection base,
    MapCellLoaded? onCellLoaded,
  ) {
    if (!_optionalContextKeys.add(key)) return;
    // Optional context is serialised globally. It must never compete with the
    // base queries that make the map navigable or trigger a burst of public
    // Overpass requests for every visible cell.
    _optionalContextQueue = _optionalContextQueue
        .then((_) async {
          final structures = await _optionalQuery(
            OverpassQueryBuilder.structuresForBounds(cell),
          );
          final trees = await _optionalQuery(
            OverpassQueryBuilder.treesForBounds(cell),
          );
          if (structures == null && trees == null) return;
          final enriched = MapFeatureCollection(
            areas: [...base.areas, if (structures != null) ...structures.areas],
            lines: [...base.lines, if (structures != null) ...structures.lines],
            pois: [
              ...base.pois,
              if (structures != null) ...structures.pois,
              if (trees != null) ...trees.pois,
            ],
          ).deduplicated();
          _memoryCells[key] = _MemoryCell(DateTime.now(), enriched);
          onCellLoaded?.call(cell, enriched);
          await _storeCell(key, enriched);
        })
        .catchError((Object error) {
          debugPrint('WildBit OSM: arricchimento opzionale fallito: $error');
        })
        .whenComplete(() {
          _optionalContextKeys.remove(key);
        });
  }

  Future<void> _storeCell(String key, MapFeatureCollection features) async {
    // Dense urban cells can contain several thousand building polygons.
    // JSON encoding them synchronously was enough to stall Android's UI
    // thread and trigger the "wait or close" ANR dialog.
    final encoded = await compute(_encodeFeatureCache, features);
    await _database
        .into(_database.cachedMapCells)
        .insertOnConflictUpdate(
          CachedMapCellsCompanion.insert(
            cellKey: key,
            fetchedAt: DateTime.now(),
            featuresJson: encoded,
          ),
        );
  }

  Future<MapFeatureCollection> _fetchBaseFromOverpass(GeoBounds cell) async {
    final query = OverpassQueryBuilder.forBounds(cell);
    return _fetchQueryFromOverpass(query);
  }

  Future<MapFeatureCollection?> _optionalQuery(String query) async {
    try {
      return await _fetchQueryFromOverpass(query);
    } catch (_) {
      return null;
    }
  }

  Future<MapFeatureCollection> _fetchQueryFromOverpass(String query) async {
    Object? lastError;
    for (final endpoint in OverpassEndpoints.all) {
      if (_endpoints.isCoolingDown(endpoint)) {
        debugPrint(
          'WildBit Overpass: salto ${Uri.parse(endpoint).host} '
          '(inattivo fino alle ${_endpoints.cooldownUntil(endpoint)!.toIso8601String()})',
        );
        continue;
      }
      try {
        debugPrint('WildBit Overpass: richiesta ${Uri.parse(endpoint).host}');
        final request = http.Request('POST', Uri.parse(endpoint))
          ..headers.addAll(const {
            // Overpass's public instances reject requests with no identifying
            // User-Agent (406 Not Acceptable) — this is required, not decorative.
            'User-Agent':
                'WildBit/1.0 (+https://wildbit.app) offline-hiking-app',
            'Accept': 'application/json',
          })
          ..bodyFields = {'data': query};
        final streamed = await _httpClient
            .send(request)
            .timeout(const Duration(seconds: 18));
        if (streamed.statusCode != 200) {
          debugPrint(
            'WildBit Overpass: ${Uri.parse(endpoint).host} HTTP ${streamed.statusCode}',
          );
          throw Exception('Overpass returned ${streamed.statusCode}');
        }

        final bytes = BytesBuilder(copy: false);
        var byteLength = 0;
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 20),
        )) {
          bytes.add(chunk);
          byteLength += chunk.length;
          if (byteLength > _maxResponseBytes) {
            throw Exception(
              'Overpass response exceeded the maximum accepted size',
            );
          }
        }
        // UTF-8 decoding, jsonDecode and OSM composition are CPU-heavy for a
        // city response. Keep all three off the Flutter UI isolate.
        final parsed = await compute(_parseOverpassPayload, bytes.takeBytes());
        debugPrint(
          'WildBit Overpass: ${Uri.parse(endpoint).host} OK '
          'areas=${parsed.areas.length} lines=${parsed.lines.length} pois=${parsed.pois.length}',
        );
        return parsed;
      } catch (error) {
        lastError = error;
        // Public Overpass instances need recovery time. A short circuit here
        // prevents every GPS/camera refresh from waiting through the same
        // dead endpoint chain again.
        _endpoints.markFailed(
          endpoint,
          serverOverloaded: error.toString().contains('502'),
        );
        debugPrint(
          'WildBit Overpass: ${Uri.parse(endpoint).host} errore $error',
        );
      }
    }
    throw lastError ?? StateError('No Overpass endpoint was available');
  }
}

MapFeatureCollection _parseOverpassPayload(Uint8List bytes) =>
    OverpassParser.parse(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );

MapFeatureCollection _decodeFeatureCache(String encoded) =>
    FeatureCacheCodec.decode(encoded);

String _encodeFeatureCache(MapFeatureCollection features) =>
    FeatureCacheCodec.encode(features);

class _CellLoadResult {
  const _CellLoadResult.available(
    this.features, {
    this.needsOptionalContext = false,
  }) : available = true;

  const _CellLoadResult.unavailable()
    : features = const MapFeatureCollection(areas: [], lines: [], pois: []),
      available = false,
      needsOptionalContext = false;

  final MapFeatureCollection features;
  final bool available;
  final bool needsOptionalContext;
}

class _MemoryCell {
  const _MemoryCell(this.fetchedAt, this.features);

  final DateTime fetchedAt;
  final MapFeatureCollection features;
}

class _OptionalContextLoad {
  const _OptionalContextLoad({
    required this.cell,
    required this.key,
    required this.base,
  });

  final GeoBounds cell;
  final String key;
  final MapFeatureCollection base;
}
