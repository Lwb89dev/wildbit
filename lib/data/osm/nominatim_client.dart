import 'dart:convert';
import 'dart:typed_data';

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
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  static const _base = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'WildBit/1.0 (+https://wildbit.app)';
  static const _requestTimeout = Duration(seconds: 8);
  static const _maxResponseBytes = 512 * 1024;

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Resolves [query] to its best-matching place, or null if nothing
  /// matched or the service is unreachable.
  Future<GeocodedPlace?> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(_base).replace(
        queryParameters: {'q': trimmed, 'format': 'jsonv2', 'limit': '1'},
      );
      final request = http.Request('GET', uri)
        ..headers.addAll(const {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        });
      final response = await _httpClient.send(request).timeout(_requestTimeout);
      final bytes = await _readBounded(
        response.stream,
        maxBytes: _maxResponseBytes,
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180) {
        return null;
      }
      return GeocodedPlace(
        displayName: first['display_name']?.toString() ?? trimmed,
        position: LatLng(lat, lon),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readBounded(
    Stream<List<int>> stream, {
    required int maxBytes,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream.timeout(_requestTimeout)) {
      length += chunk.length;
      if (length > maxBytes) {
        throw const FormatException('Nominatim response is too large');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void close() {
    if (_ownsClient) _httpClient.close();
  }
}
