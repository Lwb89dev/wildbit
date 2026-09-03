import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A single geocoding match: a place name resolved to a point.
class GeocodedPlace {
  const GeocodedPlace({required this.displayName, required this.position});

  final String displayName;
  final LatLng position;
}

/// Thin client for OpenStreetMap's own public Nominatim geocoder — turns a
/// typed place name into a position so Explore can search "around a city"
/// rather than only around the device's GPS fix.
///
/// Nominatim's usage policy caps the public instance at one request per
/// second and requires a real identifying User-Agent; this is a single,
/// user-initiated lookup per search (never polled or batched), so it stays
/// well inside that budget without needing a dedicated backoff scheme.
class NominatimClient {
  NominatimClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _base = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'WildBit/1.0 (+https://wildbit.app)';
  static const _requestTimeout = Duration(seconds: 8);
  static const _maxResponseBytes = 512 * 1024;

  final http.Client _httpClient;

  /// Resolves [query] to its best-matching place, or null if nothing
  /// matched or the service is unreachable.
  Future<GeocodedPlace?> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(_base).replace(
        queryParameters: {'q': trimmed, 'format': 'jsonv2', 'limit': '1'},
      );
      final response = await _httpClient
          .get(
            uri,
            headers: const {
              'User-Agent': _userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.length > _maxResponseBytes) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;
      return GeocodedPlace(
        displayName: first['display_name']?.toString() ?? trimmed,
        position: LatLng(lat, lon),
      );
    } catch (_) {
      return null;
    }
  }
}
