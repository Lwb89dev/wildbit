import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
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
  // The map UI has a 10 s responsiveness budget. Keep an individual public
  // Overpass endpoint attempt shorter than that so a second instance can be
  // tried while the viewport request is still relevant. A timed-out UI does
  // not cancel this repository operation: it may still stream a cell into the
  // retained map cache unless the user pans away or leaves the screen.
  static const _overpassConnectTimeout = Duration(seconds: 6);
  static const _overpassResponseTimeout = Duration(seconds: 8);
  // Buildings are orientation context, not navigational evidence. Keeping a
  // bounded nearest subset prevents a dense urban cell from retaining and
  // rebuilding thousands of decorative footprints after every GPS update.
  static const _maxOptionalBuildingsPerCell = 240;
  static const _maxMemoryCells = 12;
  // One rich cell around Bit is more useful than four delayed decorative
  // enrichments. Neighbouring cells keep their real base geometry and forest
  // biome, then gain point detail naturally as the hiker approaches them.
  static const _maxOptionalContextsPerViewport = 1;

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
  final Map<String, _OptionalContextRequest> _pendingOptionalContexts = {};
  Future<void> _optionalContextQueue = Future<void>.value();
  final _endpoints = OverpassEndpoints.instance;

  /// Read by the presentation layer after [loadFeatures]. Cached data remains
  /// usable offline; this is only set when a cell without cache cannot reach
  /// any configured Overpass endpoint.
  Object? lastLoadError;

  /// Releases decoded cells that are only an in-memory acceleration layer.
  /// The durable SQLite cache is deliberately untouched: after a pressure
  /// event the next viewport can still be restored offline without another
  /// Overpass request.
  void releaseTransientMemory() {
    _memoryCells.clear();
  }

  @visibleForTesting
  int get transientMemoryCellCount => _memoryCells.length;

  @override
  Future<MapFeatureCollection> loadFeatures(
    GeoBounds bounds, {
    MapCellLoaded? onCellLoaded,
    bool includeBuildings = true,
    bool includeIndividualTrees = true,
    bool Function()? shouldContinue,
    LatLng? priorityPosition,
    Future<void>? abortTrigger,
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
    return _loadFeaturesInternal(
      bounds,
      onCellLoaded: onCellLoaded,
      includeBuildings: includeBuildings,
      includeIndividualTrees: includeIndividualTrees,
      shouldContinue: shouldContinue,
      priorityPosition: priorityPosition,
      abortTrigger: abortTrigger,
    );
  }

  Future<MapFeatureCollection> _loadFeaturesInternal(
    GeoBounds bounds, {
    MapCellLoaded? onCellLoaded,
    required bool includeBuildings,
    required bool includeIndividualTrees,
    bool Function()? shouldContinue,
    LatLng? priorityPosition,
    Future<void>? abortTrigger,
  }) async {
    lastLoadError = null;
    final cells =
        (priorityPosition == null
                ? MapCellGrid.cellsCoveringNearestFirst(bounds)
                : MapCellGrid.cellsCoveringPrioritized(
                    bounds,
                    priority: priorityPosition,
                  ))
            .take(_maxCellsPerRequest);
    final collections = <MapFeatureCollection>[];
    final optionalContext = <_OptionalContextLoad>[];
    for (final cell in cells) {
      if (shouldContinue != null && !shouldContinue()) break;
      final result = await _loadCellShared(
        cell,
        includeBuildings,
        includeIndividualTrees,
        abortTrigger: abortTrigger,
        markEndpointSlowOnAbort: shouldContinue,
      );
      if (!result.available) continue;
      collections.add(result.features);
      onCellLoaded?.call(cell, result.features);
      if (result.needsOptionalContext) {
        optionalContext.add(
          _OptionalContextLoad(
            cell: cell,
            key: MapCellGrid.keyFor(cell),
            base: result.features,
            includeBuildings: result.includeBuildings,
            includeIndividualTrees: result.includeIndividualTrees,
          ),
        );
      }
    }

    // Buildings and individual trees are useful context, but base geography
    // for every visible cell has priority. Starting these requests only after
    // the loop prevents an optional query from delaying the user's own cell.
    for (final context in optionalContext.take(
      _maxOptionalContextsPerViewport,
    )) {
      if (shouldContinue != null && !shouldContinue()) break;
      _scheduleOptionalContext(
        context.cell,
        context.key,
        context.base,
        onCellLoaded,
        includeBuildings: context.includeBuildings,
        includeIndividualTrees: context.includeIndividualTrees,
        shouldContinue: shouldContinue,
        abortTrigger: abortTrigger,
      );
    }

    return MapFeatureCollection(
      areas: [for (final c in collections) ...c.areas],
      lines: [for (final c in collections) ...c.lines],
      pois: [for (final c in collections) ...c.pois],
    ).deduplicated();
  }

  Future<_CellLoadResult> _loadCellShared(
    GeoBounds cell,
    bool includeBuildings,
    bool includeIndividualTrees, {
    Future<void>? abortTrigger,
    bool Function()? markEndpointSlowOnAbort,
  }) async {
    final key = MapCellGrid.keyFor(cell);
    // A live viewport request owns its own cancellation signal. Sharing that
    // operation with a newer viewport would let the old request abort the
    // newer caller too. Cache/offline callers (which have no signal) still
    // coalesce through the shared-operation map below.
    if (abortTrigger != null) {
      return _loadCell(
        cell,
        key,
        includeBuildings,
        includeIndividualTrees,
        abortTrigger: abortTrigger,
        markEndpointSlowOnAbort: markEndpointSlowOnAbort,
      );
    }
    // A low-zoom request may intentionally omit buildings while a later
    // close-up request needs them. Keep those in-flight modes distinct so the
    // close-up caller cannot inherit the low-detail result.
    final activeKey =
        '$key:${includeBuildings ? 'buildings' : 'base'}:'
        '${includeIndividualTrees ? 'trees' : 'no-trees'}';
    final active = _activeCellLoads[activeKey];
    if (active != null) return active;
    final operation = _loadCell(
      cell,
      key,
      includeBuildings,
      includeIndividualTrees,
      abortTrigger: abortTrigger,
      markEndpointSlowOnAbort: markEndpointSlowOnAbort,
    );
    _activeCellLoads[activeKey] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_activeCellLoads[activeKey], operation)) {
        _activeCellLoads.remove(activeKey);
      }
    }
  }

  Future<_CellLoadResult> _loadCell(
    GeoBounds cell,
    String key,
    bool includeBuildings,
    bool includeIndividualTrees, {
    Future<void>? abortTrigger,
    bool Function()? markEndpointSlowOnAbort,
  }) async {
    final memory = _takeRememberedCell(key);
    if (memory != null &&
        DateTime.now().difference(memory.fetchedAt) < _maxCacheAge) {
      final visible = includeIndividualTrees
          ? memory.features
          : _withoutIndividualTrees(memory.features);
      return _CellLoadResult.available(
        visible,
        needsOptionalContext:
            (includeBuildings && !memory.includeBuildings) ||
            (includeIndividualTrees && !memory.includeIndividualTrees),
        includeBuildings: includeBuildings,
        includeIndividualTrees: includeIndividualTrees,
      );
    }
    final cached = await (_database.select(
      _database.cachedMapCells,
    )..where((t) => t.cellKey.equals(key))).getSingleOrNull();

    FeatureCacheEntry? decoded;
    if (cached != null &&
        FeatureCacheCodec.isCurrentFormat(cached.featuresJson)) {
      try {
        decoded = await compute(_decodeFeatureCacheEntry, cached.featuresJson);
      } catch (error) {
        // A valid-looking header is intentionally cheap to inspect. Full JSON
        // validation happens off the UI isolate; a corrupt cell simply falls
        // through to a clean network refresh.
        debugPrint('WildBit OSM: cache cella $key non valida: $error');
      }
    }

    final isFresh =
        cached != null &&
        decoded != null &&
        DateTime.now().difference(cached.fetchedAt) < _maxCacheAge;
    if (isFresh) {
      final decodedFeatures = decoded.features;
      final bounded = _limitOptionalBuildings(decodedFeatures, cell);
      final hasBuildings = bounded.areas.any(
        (area) => area.kind == MapFeatureKind.building,
      );
      final hasIndividualTrees = _hasIndividualTrees(bounded);
      final includesBuildings = decoded.includesBuildings ?? hasBuildings;
      final includesIndividualTrees =
          decoded.includesIndividualTrees ?? hasIndividualTrees;
      _rememberCell(
        key,
        _MemoryCell(
          cached.fetchedAt,
          bounded,
          includeBuildings: includesBuildings,
          includeIndividualTrees: includesIndividualTrees,
        ),
      );
      return _CellLoadResult.available(
        includeIndividualTrees ? bounded : _withoutIndividualTrees(bounded),
        needsOptionalContext:
            (includeBuildings && !includesBuildings) ||
            (includeIndividualTrees && !includesIndividualTrees),
        includeBuildings: includeBuildings,
        includeIndividualTrees: includeIndividualTrees,
      );
    }

    // Show stale map data immediately while the semantic OSM refresh runs in
    // the background. A slow/temporarily unavailable Overpass endpoint must
    // never leave the map blank for minutes when a previous cell is usable.
    if (cached != null && decoded != null) {
      final stale = decoded;
      final bounded = _limitOptionalBuildings(stale.features, cell);
      final hasBuildings = bounded.areas.any(
        (area) => area.kind == MapFeatureKind.building,
      );
      final hasIndividualTrees = _hasIndividualTrees(bounded);
      final includesBuildings = stale.includesBuildings ?? hasBuildings;
      final includesIndividualTrees =
          stale.includesIndividualTrees ?? hasIndividualTrees;
      // Treat stale disk data as session-fresh while one background refresh
      // runs, otherwise every camera/GPS callback starts another refresh.
      _rememberCell(
        key,
        _MemoryCell(
          DateTime.now(),
          bounded,
          includeBuildings: includesBuildings,
          includeIndividualTrees: includesIndividualTrees,
        ),
      );
      unawaited(
        _refreshCell(cell, key, includeBuildings, includeIndividualTrees),
      );
      return _CellLoadResult.available(
        includeIndividualTrees ? bounded : _withoutIndividualTrees(bounded),
        needsOptionalContext:
            (includeBuildings && !includesBuildings) ||
            (includeIndividualTrees && !includesIndividualTrees),
        includeBuildings: includeBuildings,
        includeIndividualTrees: includeIndividualTrees,
      );
    }

    try {
      final fetched = await _fetchBaseFromOverpass(
        cell,
        abortTrigger: abortTrigger,
        markEndpointSlowOnAbort: markEndpointSlowOnAbort,
      );
      _rememberCell(key, _MemoryCell(DateTime.now(), fetched));
      // Rendering must not wait for JSON encoding and SQLite persistence.
      // The cell is already valid at this point; cache it in the background.
      unawaited(
        _storeCell(key, fetched).catchError((Object error) {
          debugPrint('WildBit OSM: cache cella $key fallita: $error');
        }),
      );
      return _CellLoadResult.available(
        fetched,
        needsOptionalContext: true,
        includeBuildings: includeBuildings,
        includeIndividualTrees: includeIndividualTrees,
      );
    } catch (error) {
      if (error is http.RequestAbortedException) {
        // The camera moved or the widget was disposed. This is expected work
        // cancellation, not a failed OSM endpoint and not a map-data error.
        return const _CellLoadResult.unavailable();
      }
      lastLoadError ??= error;
      return const _CellLoadResult.unavailable();
    }
  }

  Future<void> _refreshCell(
    GeoBounds cell,
    String key,
    bool includeBuildings,
    bool includeIndividualTrees,
  ) async {
    try {
      final base = await _fetchBaseFromOverpass(cell);
      _rememberCell(key, _MemoryCell(DateTime.now(), base));
      await _storeCell(key, base);
      _scheduleOptionalContext(
        cell,
        key,
        base,
        null,
        includeBuildings: includeBuildings,
        includeIndividualTrees: includeIndividualTrees,
      );
    } catch (error) {
      lastLoadError ??= error;
    }
  }

  void _scheduleOptionalContext(
    GeoBounds cell,
    String key,
    MapFeatureCollection base,
    MapCellLoaded? onCellLoaded, {
    required bool includeBuildings,
    required bool includeIndividualTrees,
    bool Function()? shouldContinue,
    Future<void>? abortTrigger,
  }) {
    _pendingOptionalContexts[key] = _OptionalContextRequest(
      cell: cell,
      key: key,
      base: base,
      onCellLoaded: onCellLoaded,
      includeBuildings: includeBuildings,
      includeIndividualTrees: includeIndividualTrees,
      shouldContinue: shouldContinue,
      abortTrigger: abortTrigger,
    );
    _enqueueOptionalContext(key);
  }

  void _enqueueOptionalContext(String key) {
    if (!_optionalContextKeys.add(key)) return;
    // Optional context is serialised globally. It must never compete with the
    // base queries that make the map navigable or trigger a burst of public
    // Overpass requests for every visible cell.
    _optionalContextQueue = _optionalContextQueue
        .then((_) => _runOptionalContext(key))
        .catchError((Object error) {
          debugPrint('WildBit OSM: arricchimento opzionale fallito: $error');
        })
        .whenComplete(() {
          _optionalContextKeys.remove(key);
          // A cancelled/stale job can be replaced while it was waiting in the
          // serial queue. Start the latest version once, instead of dropping
          // its enrichment simply because the old key was still locked.
          final replacement = _pendingOptionalContexts[key];
          if (replacement != null) {
            _enqueueOptionalContext(replacement.key);
          }
        });
  }

  Future<void> _runOptionalContext(String key) async {
    final request = _pendingOptionalContexts[key];
    if (request == null) return;
    try {
      if (request.shouldContinue != null && !request.shouldContinue!()) {
        return;
      }
      final rawStructures = await _optionalQuery(
        OverpassQueryBuilder.structuresForBounds(
          request.cell,
          includeBuildings: request.includeBuildings,
        ),
        abortTrigger: request.abortTrigger,
      );
      if (request.shouldContinue != null && !request.shouldContinue!()) {
        return;
      }
      final structures = rawStructures == null
          ? null
          : _limitOptionalBuildings(rawStructures, request.cell);
      final trees = request.includeIndividualTrees
          ? await _optionalQuery(
              OverpassQueryBuilder.treesForBounds(request.cell),
              abortTrigger: request.abortTrigger,
            )
          : null;
      if (request.shouldContinue != null && !request.shouldContinue!()) {
        return;
      }
      // A newer viewport may have replaced this queued job while its first
      // network request was in flight. Never publish stale partial context
      // over the newer cell representation.
      if (!identical(_pendingOptionalContexts[key], request)) return;
      if (structures == null && trees == null) return;
      final completedBuildings = request.includeBuildings && structures != null;
      final completedIndividualTrees =
          request.includeIndividualTrees && trees != null;
      final enriched = MapFeatureCollection(
        areas: [
          ...request.base.areas,
          if (structures != null) ...structures.areas,
        ],
        lines: [
          ...request.base.lines,
          if (structures != null) ...structures.lines,
        ],
        pois: [
          ...request.base.pois,
          if (structures != null) ...structures.pois,
          if (trees != null) ...trees.pois,
        ],
      ).deduplicated();
      _rememberCell(
        key,
        _MemoryCell(
          DateTime.now(),
          enriched,
          includeBuildings: completedBuildings,
          includeIndividualTrees: completedIndividualTrees,
        ),
      );
      request.onCellLoaded?.call(request.cell, enriched);
      await _storeCell(
        request.key,
        enriched,
        includesBuildings: completedBuildings,
        includesIndividualTrees: completedIndividualTrees,
      );
    } finally {
      // Do not remove a newer job that arrived while this one was waiting or
      // fetching. The queue's completion callback will enqueue that version.
      if (identical(_pendingOptionalContexts[key], request)) {
        _pendingOptionalContexts.remove(key);
      }
    }
  }

  MapFeatureCollection _limitOptionalBuildings(
    MapFeatureCollection features,
    GeoBounds cell,
  ) {
    final buildings = features.areas
        .where((area) => area.kind == MapFeatureKind.building)
        .toList(growable: false);
    if (buildings.length <= _maxOptionalBuildingsPerCell) return features;

    final centerLat = (cell.southWest.latitude + cell.northEast.latitude) / 2;
    final centerLng = (cell.southWest.longitude + cell.northEast.longitude) / 2;
    double distanceFromCellCenter(AreaFeature area) {
      if (area.ring.isEmpty) return double.infinity;
      var lat = 0.0;
      var lng = 0.0;
      for (final point in area.ring) {
        lat += point.latitude;
        lng += point.longitude;
      }
      lat /= area.ring.length;
      lng /= area.ring.length;
      final dLat = lat - centerLat;
      final dLng = lng - centerLng;
      return dLat * dLat + dLng * dLng;
    }

    final nearest = buildings.toList(growable: true)
      ..sort((a, b) {
        final distance = distanceFromCellCenter(
          a,
        ).compareTo(distanceFromCellCenter(b));
        if (distance != 0) return distance;
        return (a.sourceId ?? '').compareTo(b.sourceId ?? '');
      });
    final retained = nearest.take(_maxOptionalBuildingsPerCell).toSet();
    return MapFeatureCollection(
      areas: [
        for (final area in features.areas)
          if (area.kind != MapFeatureKind.building || retained.contains(area))
            area,
      ],
      lines: features.lines,
      pois: features.pois,
    );
  }

  bool _hasIndividualTrees(MapFeatureCollection features) =>
      features.pois.any((poi) => poi.type == PoiType.tree);

  /// Individual `natural=tree` nodes are detail, unlike a forest polygon.
  /// Keep the complete decoded cell in the local cache, but avoid handing its
  /// thousands of point features to a broad-zoom renderer that cannot show
  /// them meaningfully anyway.
  MapFeatureCollection _withoutIndividualTrees(MapFeatureCollection features) =>
      MapFeatureCollection(
        areas: features.areas,
        lines: features.lines,
        pois: features.pois
            .where((poi) => poi.type != PoiType.tree)
            .toList(growable: false),
      );

  _MemoryCell? _takeRememberedCell(String key) {
    final cell = _memoryCells.remove(key);
    if (cell != null) _memoryCells[key] = cell;
    return cell;
  }

  void _rememberCell(String key, _MemoryCell cell) {
    // Dart's insertion-ordered map gives us a compact LRU without another
    // dependency. The complete offline cache remains in SQLite; this only
    // bounds decoded feature collections kept alive while the hiker moves.
    _memoryCells.remove(key);
    _memoryCells[key] = cell;
    while (_memoryCells.length > _maxMemoryCells) {
      _memoryCells.remove(_memoryCells.keys.first);
    }
  }

  Future<void> _storeCell(
    String key,
    MapFeatureCollection features, {
    bool includesBuildings = false,
    bool includesIndividualTrees = false,
  }) async {
    // Dense urban cells can contain several thousand building polygons.
    // JSON encoding them synchronously was enough to stall Android's UI
    // thread and trigger the "wait or close" ANR dialog.
    final encoded = await compute(
      _encodeFeatureCache,
      _FeatureCacheEncodeInput(
        features,
        includesBuildings: includesBuildings,
        includesIndividualTrees: includesIndividualTrees,
      ),
    );
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

  Future<MapFeatureCollection> _fetchBaseFromOverpass(
    GeoBounds cell, {
    Future<void>? abortTrigger,
    bool Function()? markEndpointSlowOnAbort,
  }) async {
    final query = OverpassQueryBuilder.forBounds(cell);
    return _fetchQueryFromOverpass(
      query,
      abortTrigger: abortTrigger,
      markEndpointSlowOnAbort: markEndpointSlowOnAbort,
    );
  }

  Future<MapFeatureCollection?> _optionalQuery(
    String query, {
    Future<void>? abortTrigger,
  }) async {
    try {
      return await _fetchQueryFromOverpass(query, abortTrigger: abortTrigger);
    } on http.RequestAbortedException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<MapFeatureCollection> _fetchQueryFromOverpass(
    String query, {
    Future<void>? abortTrigger,
    bool Function()? markEndpointSlowOnAbort,
  }) async {
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
        final request =
            http.AbortableRequest(
                'POST',
                Uri.parse(endpoint),
                abortTrigger: abortTrigger,
              )
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
            .timeout(_overpassConnectTimeout);
        if (streamed.statusCode != 200) {
          debugPrint(
            'WildBit Overpass: ${Uri.parse(endpoint).host} HTTP ${streamed.statusCode}',
          );
          throw OverpassHttpFailure(streamed.statusCode);
        }

        final bytes = BytesBuilder(copy: false);
        var byteLength = 0;
        await for (final chunk in streamed.stream.timeout(
          _overpassResponseTimeout,
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
      } on http.RequestAbortedException {
        // If this request is still the active viewport, the abort came from
        // the UI fetch budget rather than a pan/dispose cancellation. Briefly
        // cool down that endpoint so the next cell does not pay the same full
        // timeout again. Obsolete viewport aborts do not penalise the server.
        if (markEndpointSlowOnAbort?.call() ?? false) {
          _endpoints.markFailed(endpoint, serverOverloaded: false);
        }
        rethrow;
      } catch (error) {
        lastError = error;
        // Public Overpass instances need recovery time. A short circuit here
        // prevents every GPS/camera refresh from waiting through the same
        // dead endpoint chain again.
        _endpoints.markFailed(
          endpoint,
          serverOverloaded: OverpassEndpoints.isOverloadedFailure(error),
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

FeatureCacheEntry _decodeFeatureCacheEntry(String encoded) =>
    FeatureCacheCodec.decodeEntry(encoded);

String _encodeFeatureCache(_FeatureCacheEncodeInput input) =>
    FeatureCacheCodec.encode(
      input.features,
      includesBuildings: input.includesBuildings,
      includesIndividualTrees: input.includesIndividualTrees,
    );

class _FeatureCacheEncodeInput {
  const _FeatureCacheEncodeInput(
    this.features, {
    required this.includesBuildings,
    required this.includesIndividualTrees,
  });

  final MapFeatureCollection features;
  final bool includesBuildings;
  final bool includesIndividualTrees;
}

class _CellLoadResult {
  const _CellLoadResult.available(
    this.features, {
    this.needsOptionalContext = false,
    this.includeBuildings = true,
    this.includeIndividualTrees = true,
  }) : available = true;

  const _CellLoadResult.unavailable()
    : features = const MapFeatureCollection(areas: [], lines: [], pois: []),
      available = false,
      needsOptionalContext = false,
      includeBuildings = false,
      includeIndividualTrees = false;

  final MapFeatureCollection features;
  final bool available;
  final bool needsOptionalContext;
  final bool includeBuildings;
  final bool includeIndividualTrees;
}

class _MemoryCell {
  const _MemoryCell(
    this.fetchedAt,
    this.features, {
    this.includeBuildings = false,
    this.includeIndividualTrees = false,
  });

  final DateTime fetchedAt;
  final MapFeatureCollection features;
  final bool includeBuildings;
  final bool includeIndividualTrees;
}

class _OptionalContextLoad {
  const _OptionalContextLoad({
    required this.cell,
    required this.key,
    required this.base,
    required this.includeBuildings,
    required this.includeIndividualTrees,
  });

  final GeoBounds cell;
  final String key;
  final MapFeatureCollection base;
  final bool includeBuildings;
  final bool includeIndividualTrees;
}

class _OptionalContextRequest {
  const _OptionalContextRequest({
    required this.cell,
    required this.key,
    required this.base,
    required this.onCellLoaded,
    required this.includeBuildings,
    required this.includeIndividualTrees,
    required this.shouldContinue,
    required this.abortTrigger,
  });

  final GeoBounds cell;
  final String key;
  final MapFeatureCollection base;
  final MapCellLoaded? onCellLoaded;
  final bool includeBuildings;
  final bool includeIndividualTrees;
  final bool Function()? shouldContinue;
  final Future<void>? abortTrigger;
}
