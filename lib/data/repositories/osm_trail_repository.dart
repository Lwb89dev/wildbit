import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/hiking_trail.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/routing/route_eligibility_gate.dart';
import '../osm/trail_cache_codec.dart';
import '../osm/overpass_endpoints.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Searches named walking paths in OpenStreetMap through public Overpass
/// instances. Results stay deliberately local to the current position: it is
/// useful to hikers and avoids an unbounded, expensive global text query.
///
/// Shares [OverpassEndpoints] with [OsmMapDataRepository] rather than
/// keeping its own endpoint list and retry state — a search here must back
/// off from an endpoint the map fetcher already found struggling, not retry
/// it independently.
class OsmTrailRepository {
  OsmTrailRepository({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _distance = Distance();
  static const _maxResponseBytes = 10 * 1024 * 1024;
  static const _cacheTtl = Duration(minutes: 10);
  static const _staleGrace = Duration(hours: 24);
  static const _persistentCacheKey = 'wildbit.explore.cache.v1';
  static const _maxPersistentEntries = 24;

  final http.Client _httpClient;
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
    if (!forceRefresh && cached != null &&
        DateTime.now().difference(cached.fetchedAt) <= _cacheTtl) {
      lastResultWasStale = true;
      return cached.trails;
    }
    final queryFilter = normalizedQuery.isEmpty
        ? ''
        : '["name"~"${_escapeRegex(normalizedQuery)}",i]';
    final radiusMeters = (radiusKm * 1000).round();
    final overpassQuery =
        '''
[out:json][timeout:20];
way["highway"~"^(path|footway|track|steps|bridleway|via_ferrata)\$"]$queryFilter
  (around:$radiusMeters,${position.latitude},${position.longitude});
out tags center 150;
relation["route"~"^(hiking|foot)\$"]["network"~"^.wn\$"]$queryFilter
  (around:$radiusMeters,${position.latitude},${position.longitude});
out tags center 60;
''';

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
            .timeout(const Duration(seconds: 12));
        if (streamed.statusCode != 200) {
          throw Exception('Overpass returned ${streamed.statusCode}');
        }

        final bytes = <int>[];
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 15),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > _maxResponseBytes) {
            throw Exception(
              'Overpass response exceeded the maximum accepted size',
            );
          }
        }
        final trails = _parse(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          position,
        );
        _cache[cacheKey] = _TrailCacheEntry(
          fetchedAt: DateTime.now(),
          trails: trails,
        );
        unawaited(_persistCache());
        return trails;
      } catch (error) {
        lastError = error;
        _endpoints.markFailed(
          endpoint,
          serverOverloaded: error.toString().contains('502'),
        );
      }
    }
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <= _staleGrace) {
      lastResultWasStale = true;
      return cached.trails;
    }
    throw lastError ?? StateError('No Overpass endpoint was available');
  }

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
        final fetchedAt = DateTime.tryParse(value['fetchedAt'] as String? ?? '');
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

  List<HikingTrail> _parse(Map<String, dynamic> json, LatLng origin) {
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

      if (element['type'] == 'relation') {
        final id = 'osm-relation-${element['id']}';
        if (!seen.add(id)) continue;
        final metadata = RouteMetadata.fromOsmTags(tags);
        trails.add(
          HikingTrail(
            id: id,
            name: name,
            ref: tags['ref'],
            position: LatLng(lat.toDouble(), lon.toDouble()),
            metadata: metadata,
            eligibility: RouteEligibilityGate.evaluate(metadata),
            route: HikingRouteMembership(
              relationId: element['id'].toString(),
              ref: tags['ref'],
              name: tags['name'],
              network: tags['network'],
            ),
            lengthKm: double.tryParse(tags['distance'] ?? ''),
          ),
        );
        continue;
      }

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

  double _rank(HikingTrail trail, double distanceMeters) {
    // A curated route relation (a maintained, numbered/named long-distance
    // trail) is what users actually mean by "recommended" — it should always
    // surface above generic way segments, regardless of radius, hence the
    // fixed offset dwarfing any in-range distance value.
    if (trail.isCuratedRoute) {
      return -1000000 + trail.route!.displayPriority * 1000 + distanceMeters;
    }
    final isNamed = trail.name != 'Sentiero escursionistico';
    final hasRouteRelation = trail.metadata.hikingRoutes.isNotEmpty;
    final isRestricted = trail.eligibility.status == RouteProposalStatus.doNotOffer;
    return distanceMeters +
        (isNamed ? 0 : 4000) +
        (hasRouteRelation ? 0 : 1000) +
        (isRestricted ? 10000 : 0);
  }

  // `String.replaceAll` takes the replacement literally — it has no
  // `$1`-backreference support (that's a JS/PCRE `.replace` idiom, not a
  // Dart one). `replaceAllMapped` is what actually re-inserts the matched
  // character with a backslash in front of it.
  //
  // `"` is included even though it isn't a regex metacharacter: this value
  // is embedded inside an Overpass QL string literal (`["name"~"..."]`), and
  // an unescaped `"` in user input would close that literal early, letting
  // arbitrary Overpass QL be appended to the query (e.g. via the Explore
  // search box) — an injection into shared public infrastructure, not just
  // a regex-matching bug.
  String _escapeRegex(String value) => value.replaceAllMapped(
    RegExp(r'([\\^$.*+?()[\]{}|"])'),
    (match) => '\\${match[0]}',
  );
}

class _TrailCacheEntry {
  const _TrailCacheEntry({required this.fetchedAt, required this.trails});

  final DateTime fetchedAt;
  final List<HikingTrail> trails;
}
