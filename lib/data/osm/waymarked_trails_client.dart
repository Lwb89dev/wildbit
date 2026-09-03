import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A curated hiking route resolved from Waymarked Trails, positioned and
/// with its real extension — not just a bare geometry match.
class WaymarkedRouteDetails {
  const WaymarkedRouteDetails({
    required this.relationId,
    required this.name,
    required this.center,
    this.ref,
    this.group,
    this.lengthKm,
    this.difficulty,
  });

  final int relationId;
  final String name;
  final LatLng center;
  final String? ref;
  final String? group;
  final double? lengthKm;

  /// CAI's own grading (`cai_scale`) when present, else the international
  /// `sac_scale` — both share the same T1–T6-equivalent vocabulary.
  final String? difficulty;
}

/// Thin client for Waymarked Trails' public hiking API.
///
/// Waymarked Trails is a query/rendering layer over OpenStreetMap's own
/// `route=hiking` relations — it invents nothing. In Italy that matters
/// concretely: CAI edits its official trail network directly in OSM (a 2016
/// CAI/Wikimedia Italia agreement), tagging it with CAI's own `cai_scale`
/// difficulty and waymark symbols, so a CAI-numbered trail that has been
/// synced into OSM already carries that classification here. Coverage is
/// worldwide, not Italy-specific, since it indexes every OSM hiking relation.
///
/// It is a single, well-established community service, unlike the rotating
/// pool of public Overpass instances — no fallback list, but the same
/// courtesy applies: bounded requests, a real User-Agent, no unbounded
/// fan-out. The endpoint paths and the `bbox` projection (Web Mercator /
/// EPSG:3857 metres, not plain lat/lon degrees) are undocumented but are
/// exactly what waymarkedtrails.org's own frontend calls from the browser,
/// discovered by reading its request traffic — so a WildBit query costs the
/// service no more than a visitor panning the map.
class WaymarkedTrailsClient {
  WaymarkedTrailsClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _base = 'https://hiking.waymarkedtrails.org/api/v1';
  static const _userAgent = 'WildBit/1.0 (+https://wildbit.app)';
  static const _requestTimeout = Duration(seconds: 8);
  static const _maxResponseBytes = 2 * 1024 * 1024;

  /// A full-geometry `details` response is far larger than the summary one
  /// (every member way's own coordinate list, not just a bounding box) —
  /// a continental route can legitimately need several megabytes. Still
  /// bounded, so a pathological response can't be read into memory
  /// unbounded.
  static const _maxGeometryResponseBytes = 20 * 1024 * 1024;
  static const _geometryRequestTimeout = Duration(seconds: 20);

  /// Caps how many area matches get a full `details` lookup (for real
  /// length and position) per search — the area listing itself carries no
  /// coordinates per route, and turning one search into dozens of detail
  /// requests would be an unfair multiplier on a shared free service.
  static const _maxDetailFetches = 15;

  final http.Client _httpClient;

  /// Curated routes near [position], ranked by network importance
  /// (national/regional routes first) and capped to [_maxDetailFetches]
  /// before their real length/position is resolved.
  Future<List<WaymarkedRouteDetails>> nearby({
    required LatLng position,
    required double radiusKm,
  }) async {
    final summaries = await _listByArea(position, radiusKm);
    if (summaries.isEmpty) return const [];
    summaries.sort(
      (a, b) => _priority(a.group).compareTo(_priority(b.group)),
    );
    final capped = summaries.take(_maxDetailFetches);
    final details = await Future.wait(
      capped.map((s) => _detailsOrNull(s.relationId)),
    );
    return [for (final detail in details) ?detail];
  }

  Future<List<_WaymarkedRouteSummary>> _listByArea(
    LatLng position,
    double radiusKm,
  ) async {
    final (centerX, centerY) = _toWebMercator(position);
    final radiusMeters = radiusKm.clamp(1, 100) * 1000;
    final bbox = [
      centerX - radiusMeters,
      centerY - radiusMeters,
      centerX + radiusMeters,
      centerY + radiusMeters,
    ].join(',');
    final uri = Uri.parse(
      '$_base/list/by_area',
    ).replace(queryParameters: {'bbox': bbox, 'limit': '40'});
    final decoded = jsonDecode(await _get(uri)) as Map<String, dynamic>;
    final results = decoded['results'] as List? ?? const [];
    return [
      for (final raw in results)
        if (raw is Map && raw['id'] != null)
          _WaymarkedRouteSummary(
            relationId: (raw['id'] as num).toInt(),
            group: raw['group'] as String?,
          ),
    ];
  }

  Future<WaymarkedRouteDetails?> _detailsOrNull(int relationId) async {
    try {
      final uri = Uri.parse('$_base/details/relation/$relationId');
      final decoded = jsonDecode(await _get(uri)) as Map<String, dynamic>;
      final bbox = decoded['bbox'] as List?;
      if (bbox == null || bbox.length != 4) return null;
      final center = _fromWebMercator(
        ((bbox[0] as num).toDouble() + (bbox[2] as num).toDouble()) / 2,
        ((bbox[1] as num).toDouble() + (bbox[3] as num).toDouble()) / 2,
      );
      final tags =
          (decoded['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      // `official_length` is only present when OSM's own `distance` tag is
      // set. Most routes don't have one, but Waymarked Trails still computes
      // a real length from the resolved geometry under `route.length` —
      // falling back to that means a length still shows for the common case.
      final route = decoded['route'] as Map?;
      final lengthMeters =
          (decoded['official_length'] as num?)?.toDouble() ??
          (route?['length'] as num?)?.toDouble();
      final name =
          decoded['name'] as String? ?? decoded['ref'] as String? ?? 'Percorso';
      return WaymarkedRouteDetails(
        relationId: relationId,
        name: name,
        center: center,
        ref: decoded['ref'] as String?,
        group: decoded['group'] as String?,
        lengthKm: lengthMeters != null ? lengthMeters / 1000 : null,
        difficulty:
            tags['cai_scale'] as String? ?? tags['sac_scale'] as String?,
      );
    } catch (_) {
      // One route's detail lookup failing must not drop the whole search.
      return null;
    }
  }

  /// The route's full geometry, in order, for corridor/offline-download use.
  /// Only the `main` (primary) branch is used — optional alternate
  /// `appendices` variants are not part of the corridor.
  ///
  /// Throws if the route can't be resolved or its geometry is too large to
  /// handle responsibly; callers should show this as "route unavailable"
  /// rather than silently drawing nothing.
  Future<List<LatLng>> routeGeometry(int relationId) async {
    final uri = Uri.parse('$_base/details/relation/$relationId');
    final body = await _get(
      uri,
      timeout: _geometryRequestTimeout,
      maxBytes: _maxGeometryResponseBytes,
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final route = decoded['route'] as Map?;
    final main = route?['main'] as List? ?? const [];
    final points = <LatLng>[];
    for (final rawSegment in main) {
      if (rawSegment is! Map) continue;
      for (final rawWay in rawSegment['ways'] as List? ?? const []) {
        if (rawWay is! Map) continue;
        final geometry = rawWay['geometry'] as Map?;
        final coordinates = geometry?['coordinates'] as List? ?? const [];
        for (final rawPoint in coordinates) {
          if (rawPoint is! List || rawPoint.length < 2) continue;
          final x = rawPoint[0];
          final y = rawPoint[1];
          if (x is! num || y is! num) continue;
          final point = _fromWebMercator(x.toDouble(), y.toDouble());
          // Consecutive ways share their joining node; skip the exact repeat
          // rather than drawing/measuring a zero-length segment.
          if (points.isEmpty || points.last != point) points.add(point);
        }
      }
    }
    if (points.length < 2) {
      throw StateError('Route $relationId has no usable geometry');
    }
    return points;
  }

  Future<String> _get(
    Uri uri, {
    Duration? timeout,
    int? maxBytes,
  }) async {
    final response = await _httpClient
        .get(
          uri,
          headers: const {
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          },
        )
        .timeout(timeout ?? _requestTimeout);
    if (response.statusCode != 200) {
      throw Exception('Waymarked Trails returned ${response.statusCode}');
    }
    if (response.bodyBytes.length > (maxBytes ?? _maxResponseBytes)) {
      throw Exception(
        'Waymarked Trails response exceeded the maximum accepted size',
      );
    }
    return response.body;
  }

  static int _priority(String? group) => switch (group) {
    'INT' => 0,
    'NAT' => 1,
    'REG' => 2,
    'AL2' || 'AL3' || 'AL4' => 3,
    'LOC' => 4,
    _ => 5,
  };

  // Waymarked Trails' map (and therefore its `bbox` query parameter) works
  // in the same Web Mercator projection as OSM/Google tiles, not raw
  // lat/lon degrees — verified against a known route's own returned bbox.
  static (double, double) _toWebMercator(LatLng position) {
    const earthRadius = 6378137.0;
    final x = position.longitude * math.pi / 180 * earthRadius;
    final y =
        math.log(
          math.tan(math.pi / 4 + position.latitude * math.pi / 360),
        ) *
        earthRadius;
    return (x, y);
  }

  static LatLng _fromWebMercator(double x, double y) {
    const earthRadius = 6378137.0;
    final longitude = x / earthRadius * 180 / math.pi;
    final latitude =
        (2 * math.atan(math.exp(y / earthRadius)) - math.pi / 2) *
        180 /
        math.pi;
    return LatLng(latitude, longitude);
  }
}

class _WaymarkedRouteSummary {
  const _WaymarkedRouteSummary({required this.relationId, this.group});

  final int relationId;
  final String? group;
}
