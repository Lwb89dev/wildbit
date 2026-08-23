import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/hiking_trail.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/routing/route_eligibility_gate.dart';

/// Searches named walking paths in OpenStreetMap through public Overpass
/// instances. Results stay deliberately local to the current position: it is
/// useful to hikers and avoids an unbounded, expensive global text query.
class OsmTrailRepository {
  OsmTrailRepository({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  static const _distance = Distance();

  final http.Client _httpClient;

  Future<List<HikingTrail>> findNearby({
    required LatLng position,
    double radiusKm = 12,
    String query = '',
  }) async {
    final normalizedQuery = query.trim();
    final queryFilter = normalizedQuery.isEmpty
        ? ''
        : '["name"~"${_escapeRegex(normalizedQuery)}",i]';
    final overpassQuery =
        '''
[out:json][timeout:20];
way["highway"~"^(path|footway|track|bridleway)\$"]$queryFilter
  (around:${(radiusKm * 1000).round()},${position.latitude},${position.longitude});
out tags center 150;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final request = http.Request('POST', Uri.parse(endpoint))
          ..headers.addAll(const {
            'User-Agent': 'WildBit/1.0 (+https://wildbit.app)',
            'Accept': 'application/json',
          })
          ..bodyFields = {'data': overpassQuery};
        final response = await _httpClient
            .send(request)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw Exception('Overpass returned ${response.statusCode}');
        }
        final body = await response.stream.bytesToString();
        return _parse(jsonDecode(body) as Map<String, dynamic>, position);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('No Overpass endpoint was available');
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
    trails.sort(
      (a, b) => _distance
          .as(LengthUnit.Meter, origin, a.position)
          .compareTo(_distance.as(LengthUnit.Meter, origin, b.position)),
    );
    return trails;
  }

  String _escapeRegex(String value) =>
      value.replaceAll(RegExp(r'([\\^$.*+?()[\]{}|])'), r'\$1');
}
