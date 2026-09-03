import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/hiking_trail.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/routing/route_eligibility_gate.dart';
import '../osm/trail_cache_codec.dart';
import '../osm/overpass_endpoints.dart';
import '../osm/trail_query_builder.dart';
import '../osm/waymarked_trails_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Searches walking paths and curated hiking routes near the user. Results
/// stay deliberately local to the current position: it is useful to hikers
/// and avoids an unbounded, expensive global text query.
///
/// Two independent sources are merged: bare OSM way segments via public
/// Overpass instances (shares [OverpassEndpoints] with
/// [OsmMapDataRepository] rather than keeping its own endpoint list and
/// retry state — a search here must back off from an endpoint the map
/// fetcher already found struggling, not retry it independently), and
/// curated hiking route relations via [WaymarkedTrailsClient], which
/// resolves them with a real length and position instead of raw,
/// sometimes-missing Overpass tags.
class OsmTrailRepository {
  OsmTrailRepository({http.Client? httpClient, WaymarkedTrailsClient? waymarkedClient})
    : _httpClient = httpClient ?? http.Client(),
      _waymarkedClient = waymarkedClient ?? WaymarkedTrailsClient(httpClient: httpClient);

  static const _distance = Distance();
  static const _maxResponseBytes = 10 * 1024 * 1024;
  static const _cacheTtl = Duration(minutes: 10);
  static const _staleGrace = Duration(hours: 24);
  static const _persistentCacheKey = 'wildbit.explore.cache.v1';
  static const _maxPersistentEntries = 24;
  static const _endpointConnectTimeout = Duration(seconds: 6);
  static const _endpointResponseTimeout = Duration(seconds: 8);

  final http.Client _httpClient;
  final WaymarkedTrailsClient _waymarkedClient;
  final _endpoints = OverpassEndpoints.instance;
  final _cache = <String, _TrailCacheEntry>{};
  Future<void>? _persistentLoad;

  /// True when the last result came from a local cache because the network
  /// was unavailable. The UI can explain stale data without hiding it.
  bool lastResultWasStale = false;

  Future<List<HikingTrail>> findNearby({
    required LatLng position,
    double radiusKm = 12,
    String query = '',
    bool forceRefresh = false,
  }) async {
    await _loadPersistentCache();
    lastResultWasStale = false;
    final normalizedQuery = query.trim();
    final cacheKey = _cacheKey(position, radiusKm, normalizedQuery);
    final cached = _cache[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) <= _cacheTtl) {
      lastResultWasStale = true;
      return cached.trails;
    }
    // Started together and awaited independently: Overpass and Waymarked
    // Trails are unrelated services, so one being slow or unreachable must
    // never block or void a result the other already has. Awaiting the way
    // fetch to completion before even starting the Waymarked Trails request
    // (or vice versa) would turn a single flaky endpoint into a total
    // search failure even when the other source answered fine.
    final wayFuture = _fetchWayTrails(
      position: position,
      radiusKm: radiusKm,
      normalizedQuery: normalizedQuery,
    );
    // The error handler is attached here, at creation time, not after
    // `wayFuture` is awaited below — a Future that fails with nothing yet
    // listening is reported by Dart as unhandled even if a try/catch around
    // a later `await` of it would otherwise have caught it. Converting the
    // failure into an empty list immediately closes that window.
    final curatedFuture = _waymarkedClient
        .nearby(position: position, radiusKm: radiusKm)
        .then<List<WaymarkedRouteDetails>>(
          (value) => value,
          onError: (_) => const <WaymarkedRouteDetails>[],
        );

    List<HikingTrail> wayTrails = const [];
    Object? wayError;
    try {
      wayTrails = await wayFuture;
    } catch (error) {
      wayError = error;
    }

    final curated = await curatedFuture;

    if (wayError != null && curated.isEmpty) {
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) <= _staleGrace) {
        lastResultWasStale = true;
        return cached.trails;
      }
      throw wayError;
    }

    final curatedTrails = [
      for (final route in curated)
        if (normalizedQuery.isEmpty || _matchesQuery(route, normalizedQuery))
          _toHikingTrail(route),
    ];

    final trails = [...wayTrails, ...curatedTrails];
    trails.sort((a, b) {
      final aDistance = _distance.as(LengthUnit.Meter, position, a.position);
      final bDistance = _distance.as(LengthUnit.Meter, position, b.position);
      final byRank = _rank(a, aDistance).compareTo(_rank(b, bDistance));
      if (byRank != 0) return byRank;
      final byDistance = aDistance.compareTo(bDistance);
      return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
    });

    _cache[cacheKey] = _TrailCacheEntry(fetchedAt: DateTime.now(), trails: trails);
    unawaited(_persistCache());
    return trails;
  }

  /// Runs the Overpass endpoint-retry loop for bare way segments. Throws the
  /// last error once every endpoint has been tried or is cooling down.
  Future<List<HikingTrail>> _fetchWayTrails({
    required LatLng position,
    required double radiusKm,
    required String normalizedQuery,
  }) async {
    final overpassQuery = TrailQueryBuilder.nearby(
      position: position,
      radiusKm: radiusKm,
      query: normalizedQuery,
    );

    Object? lastError;
    for (final endpoint in OverpassEndpoints.all) {
      if (_endpoints.isCoolingDown(endpoint)) continue;
      try {
        final request = http.Request('POST', Uri.parse(endpoint))
          ..headers.addAll(const {
            'User-Agent': 'WildBit/1.0 (+https://wildbit.app)',
            'Accept': 'application/json',
          })
          ..bodyFields = {'data': overpassQuery};
        final streamed = await _httpClient
            .send(request)
            .timeout(_endpointConnectTimeout);
        if (streamed.statusCode != 200) {
          throw OverpassHttpFailure(streamed.statusCode);
        }

        final bytes = BytesBuilder(copy: false);
        var byteLength = 0;
        await for (final chunk in streamed.stream.timeout(
          _endpointResponseTimeout,
        )) {
          bytes.add(chunk);
          byteLength += chunk.length;
          if (byteLength > _maxResponseBytes) {
            throw Exception(
              'Overpass response exceeded the maximum accepted size',
            );
          }
        }
        // JSON decoding and eligibility classification can be expensive at a
        // 100 km radius. Keep the composition off Flutter's UI isolate, just
        // like the main map parser.
        return await compute(
          _parseTrailPayload,
          _TrailParseInput(
            bytes.takeBytes(),
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        );
      } catch (error) {
        lastError = error;
        _endpoints.markFailed(
          endpoint,
          serverOverloaded: OverpassEndpoints.isOverloadedFailure(error),
        );
      }
    }
    throw lastError ?? StateError('No Overpass endpoint was available');
  }

  bool _matchesQuery(WaymarkedRouteDetails route, String query) {
    final needle = query.toLowerCase();
    return route.name.toLowerCase().contains(needle) ||
        (route.ref?.toLowerCase().contains(needle) ?? false);
  }

  HikingTrail _toHikingTrail(WaymarkedRouteDetails route) => HikingTrail(
    id: 'wmt-relation-${route.relationId}',
    name: route.name,
    ref: route.ref,
    position: route.center,
    metadata: RouteMetadata(sacScale: route.difficulty),
    route: HikingRouteMembership(
      relationId: route.relationId.toString(),
      ref: route.ref,
      name: route.name,
      network: route.group,
    ),
    lengthKm: route.lengthKm,
  );

  // Hashed rather than kept as plain "lat:lon:..." text: this key is also
  // used verbatim as the persisted SharedPreferences key in
  // `_persistCache`, and Android's default Auto Backup would otherwise
  // carry the user's past search coordinates off-device in plaintext.
  String _cacheKey(LatLng position, double radiusKm, String query) {
    final raw =
        '${position.latitude.toStringAsFixed(3)}:'
        '${position.longitude.toStringAsFixed(3)}:'
        '${radiusKm.toStringAsFixed(1)}:${query.toLowerCase()}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<void> _loadPersistentCache() {
    return _persistentLoad ??= _readPersistentCache();
  }

  Future<void> _readPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentCacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final entries = decoded['entries'];
      if (entries is! Map) return;
      for (final entry in entries.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final fetchedAt = DateTime.tryParse(
          value['fetchedAt'] as String? ?? '',
        );
        final payload = value['payload'] as String?;
        if (fetchedAt == null || payload == null) continue;
        final trails = TrailCacheCodec.decode(payload);
        _cache[entry.key as String] = _TrailCacheEntry(
          fetchedAt: fetchedAt,
          trails: trails,
        );
      }
    } catch (_) {
      // Explore must remain usable if preferences are unavailable/corrupt.
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sorted = _cache.entries.toList()
        ..sort((a, b) => b.value.fetchedAt.compareTo(a.value.fetchedAt));
      final entries = <String, dynamic>{};
      for (final entry in sorted.take(_maxPersistentEntries)) {
        entries[entry.key] = {
          'fetchedAt': entry.value.fetchedAt.toIso8601String(),
          'payload': TrailCacheCodec.encode(entry.value.trails),
        };
      }
      await prefs.setString(
        _persistentCacheKey,
        jsonEncode({'version': 1, 'entries': entries}),
      );
    } catch (_) {
      // The in-memory cache remains the fast path when persistence fails.
    }
  }

  // Curated hiking route relations come from WaymarkedTrailsClient instead
  // (see findNearby) — this only ever parses bare way segments now.
  static List<HikingTrail> _parse(Map<String, dynamic> json, LatLng origin) {
    final trails = <HikingTrail>[];
    final seen = <String>{};
    for (final rawElement in json['elements'] as List? ?? const []) {
      final element = rawElement as Map<String, dynamic>;
      final tags =
          (element['tags'] as Map?)?.cast<String, String>() ?? const {};
      final name = tags['name'] ?? tags['ref'] ?? 'Sentiero escursionistico';
      final center = element['center'] as Map?;
      if (center == null) continue;
      final lat = center['lat'] as num?;
      final lon = center['lon'] as num?;
      if (lat == null || lon == null) continue;

      final id = 'osm-way-${element['id']}';
      if (!seen.add(id)) continue;
      final metadata = RouteMetadata.fromOsmTags(
        tags,
        wayId: element['id']?.toString(),
      );
      trails.add(
        HikingTrail(
          id: id,
          name: name,
          ref: tags['ref'],
          position: LatLng(lat.toDouble(), lon.toDouble()),
          metadata: metadata,
          // Search returns a centre point, never a complete reviewed route.
          eligibility: RouteEligibilityGate.evaluate(metadata),
          lengthKm: _lengthKm(tags['distance']),
        ),
      );
    }
    trails.sort((a, b) {
      final aDistance = _distance.as(LengthUnit.Meter, origin, a.position);
      final bDistance = _distance.as(LengthUnit.Meter, origin, b.position);
      final byRank = _rank(a, aDistance).compareTo(_rank(b, bDistance));
      if (byRank != 0) return byRank;
      final byDistance = aDistance.compareTo(bDistance);
      return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
    });
    return trails;
  }

  static double _rank(HikingTrail trail, double distanceMeters) {
    // A curated route relation (a maintained, numbered/named long-distance
    // trail) is what users actually mean by "recommended" — it should always
    // surface above generic way segments, regardless of radius, hence the
    // fixed offset dwarfing any in-range distance value.
    if (trail.isCuratedRoute) {
      return -1000000 + trail.route!.displayPriority * 1000 + distanceMeters;
    }
    final isNamed = trail.name != 'Sentiero escursionistico';
    final hasRouteRelation = trail.metadata.hikingRoutes.isNotEmpty;
    final isRestricted =
        trail.eligibility.status == RouteProposalStatus.doNotOffer;
    return distanceMeters +
        (isNamed ? 0 : 4000) +
        (hasRouteRelation ? 0 : 1000) +
        (isRestricted ? 10000 : 0);
  }

  static double? _lengthKm(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'^\s*(\d+(?:[\.,]\d+)?)\s*(km|kilomet(?:er|re|ri)|m|met(?:er|re|ri))?\s*$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null || value < 0) return null;
    final unit = match.group(2)?.toLowerCase();
    return unit == 'm' || unit?.startsWith('met') == true
        ? value / 1000
        : value;
  }
}

List<HikingTrail> _parseTrailPayload(_TrailParseInput input) =>
    OsmTrailRepository._parse(
      jsonDecode(utf8.decode(input.bytes)) as Map<String, dynamic>,
      LatLng(input.latitude, input.longitude),
    );

class _TrailParseInput {
  const _TrailParseInput(
    this.bytes, {
    required this.latitude,
    required this.longitude,
  });

  final Uint8List bytes;
  final double latitude;
  final double longitude;
}

class _TrailCacheEntry {
  const _TrailCacheEntry({required this.fetchedAt, required this.trails});

  final DateTime fetchedAt;
  final List<HikingTrail> trails;
}
