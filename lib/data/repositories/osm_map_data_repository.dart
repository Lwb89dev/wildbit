import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/repositories/map_data_repository.dart';
import '../../storage/database.dart';
import '../osm/feature_cache_codec.dart';
import '../osm/map_cell_grid.dart';
import '../osm/overpass_parser.dart';
import '../osm/overpass_query_builder.dart';
import '../test_data/test_region.dart';
import '../test_data/mixed_preview_region.dart';

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

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
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
  Future<MapFeatureCollection>? _activeLoad;
  final _endpointCooldownUntil = <String, DateTime>{};

  /// Read by the presentation layer after [loadFeatures]. Cached data remains
  /// usable offline; this is only set when a cell without cache cannot reach
  /// any configured Overpass endpoint.
  Object? lastLoadError;

  @override
  Future<MapFeatureCollection> loadFeatures(GeoBounds bounds) async {
    if (offlinePreview) {
      lastLoadError = null;
      return mixedPreview ? mixedPreviewFeatures : testRegionFeatures;
    }
    // GPS updates, camera settling and the initial viewport can request the
    // same area within a few milliseconds. Share the in-flight operation;
    // otherwise each caller opens its own set of Overpass connections.
    final active = _activeLoad;
    if (active != null) return active;
    final operation = _loadFeaturesInternal(bounds);
    _activeLoad = operation;
    try {
      return await operation;
    } finally {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    }
  }

  Future<MapFeatureCollection> _loadFeaturesInternal(GeoBounds bounds) async {
    lastLoadError = null;
    final cells = MapCellGrid.cellsCovering(bounds).take(_maxCellsPerRequest);
    final collections = <MapFeatureCollection>[];
    for (final cell in cells) {
      collections.add(await _loadCell(cell));
    }

    return MapFeatureCollection(
      areas: [for (final c in collections) ...c.areas],
      lines: [for (final c in collections) ...c.lines],
      pois: [for (final c in collections) ...c.pois],
    ).deduplicated();
  }

  Future<MapFeatureCollection> _loadCell(GeoBounds cell) async {
    final key = MapCellGrid.keyFor(cell);
    final cached = await (_database.select(
      _database.cachedMapCells,
    )..where((t) => t.cellKey.equals(key))).getSingleOrNull();

    final isFresh =
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _maxCacheAge &&
        FeatureCacheCodec.isCurrentFormat(cached.featuresJson);
    if (isFresh) return FeatureCacheCodec.decode(cached.featuresJson);

    // Show stale map data immediately while the semantic OSM refresh runs in
    // the background. A slow/temporarily unavailable Overpass endpoint must
    // never leave the map blank for minutes when a previous cell is usable.
    if (cached != null &&
        FeatureCacheCodec.isCurrentFormat(cached.featuresJson)) {
      final stale = FeatureCacheCodec.decode(cached.featuresJson);
      unawaited(_refreshCell(cell, key));
      return stale;
    }

    try {
      final fetched = await _fetchFromOverpass(cell);
      await _storeCell(key, fetched);
      return fetched;
    } catch (error) {
      lastLoadError ??= error;
      if (cached != null) return FeatureCacheCodec.decode(cached.featuresJson);
      return const MapFeatureCollection(areas: [], lines: [], pois: []);
    }
  }

  Future<void> _refreshCell(GeoBounds cell, String key) async {
    try {
      await _storeCell(key, await _fetchFromOverpass(cell));
    } catch (error) {
      lastLoadError ??= error;
    }
  }

  Future<void> _storeCell(String key, MapFeatureCollection features) {
    return _database
        .into(_database.cachedMapCells)
        .insertOnConflictUpdate(
          CachedMapCellsCompanion.insert(
            cellKey: key,
            fetchedAt: DateTime.now(),
            featuresJson: FeatureCacheCodec.encode(features),
          ),
        );
  }

  Future<MapFeatureCollection> _fetchFromOverpass(GeoBounds cell) async {
    final query = OverpassQueryBuilder.forBounds(cell);
    final structuresQuery = OverpassQueryBuilder.structuresForBounds(cell);
    final treesQuery = OverpassQueryBuilder.treesForBounds(cell);
    // Base geography first: bursting three queries per cell together causes
    // public Overpass instances to answer with 502 under load.
    final base = await _fetchQueryFromOverpass(query);
    final optional = await Future.wait<MapFeatureCollection?>([
      _optionalQuery(structuresQuery),
      _optionalQuery(treesQuery),
    ]);
    final structures = optional[0];
    final trees = optional[1];
    // Structures and detailed vegetation are optional context. Never discard
    // valid roads, trails or water when either query is unavailable.
    return MapFeatureCollection(
      areas: [...base.areas, if (structures != null) ...structures.areas],
      lines: [...base.lines, if (structures != null) ...structures.lines],
      pois: [
        ...base.pois,
        if (structures != null) ...structures.pois,
        if (trees != null) ...trees.pois,
      ],
    ).deduplicated();
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
    for (final endpoint in _endpoints) {
      final cooldown = _endpointCooldownUntil[endpoint];
      if (cooldown != null && cooldown.isAfter(DateTime.now())) {
        debugPrint(
          'WildBit Overpass: salto ${Uri.parse(endpoint).host} '
          '(inattivo fino alle ${cooldown.toIso8601String()})',
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

        final bytes = <int>[];
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 20),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > _maxResponseBytes) {
            throw Exception(
              'Overpass response exceeded the maximum accepted size',
            );
          }
        }
        final parsed = OverpassParser.parse(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        );
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
        final seconds = error.toString().contains('502') ? 45 : 25;
        _endpointCooldownUntil[endpoint] = DateTime.now().add(
          Duration(seconds: seconds),
        );
        debugPrint(
          'WildBit Overpass: ${Uri.parse(endpoint).host} errore $error',
        );
      }
    }
    throw lastError ?? StateError('No Overpass endpoint was available');
  }
}
