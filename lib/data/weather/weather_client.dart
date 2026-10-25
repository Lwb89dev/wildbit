import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/weather_snapshot.dart';

abstract interface class WeatherClient {
  Future<WeatherSnapshot> fetchCurrent(LatLng position);
}

/// Open-Meteo current conditions client. The request is intentionally small
/// and bounded: one current record, no hourly forecast and no large response
/// retained in memory.
class OpenMeteoClient implements WeatherClient {
  OpenMeteoClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  static const _endpoint = 'https://api.open-meteo.com/v1/forecast';
  static const _requestTimeout = Duration(seconds: 8);
  static const _maxResponseBytes = 64 * 1024;

  final http.Client _httpClient;
  final bool _ownsClient;

  @override
  Future<WeatherSnapshot> fetchCurrent(LatLng position) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        // A third-party service only needs the weather cell, not the hiker:
        // two decimals (about 1 km) match the finest forecast grids, where
        // four decimals disclosed the position to about 11 m.
        'latitude': position.latitude.toStringAsFixed(2),
        'longitude': position.longitude.toStringAsFixed(2),
        'current': [
          'temperature_2m',
          'precipitation',
          'rain',
          'snowfall',
          'cloud_cover',
          'visibility',
          'weather_code',
          'wind_speed_10m',
          'wind_direction_10m',
          'is_day',
        ].join(','),
        'timezone': 'auto',
        'forecast_days': '1',
      },
    );
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'application/json';
    final response = await _httpClient.send(request).timeout(_requestTimeout);
    final bytes = await _readBounded(response.stream);
    if (response.statusCode != 200) {
      throw WeatherFetchException(
        'Weather service returned ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const WeatherFetchException('Weather response is invalid');
    }
    final current = decoded['current'];
    if (current is! Map) {
      throw const WeatherFetchException('Weather response has no current data');
    }

    double number(String key, {double fallback = 0}) =>
        (current[key] as num?)?.toDouble() ?? fallback;
    int integer(String key) => (current[key] as num?)?.toInt() ?? 0;

    return WeatherSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      fetchedAt: DateTime.now(),
      weatherCode: integer('weather_code'),
      temperatureCelsius: number('temperature_2m'),
      precipitationMm: number('precipitation'),
      rainMm: number('rain'),
      snowfallCm: number('snowfall'),
      cloudCoverPercent: number('cloud_cover'),
      visibilityMeters: number('visibility', fallback: double.infinity),
      windSpeedKmh: number('wind_speed_10m'),
      windDirectionDegrees: number('wind_direction_10m'),
      isDay: integer('is_day') == 1,
    );
  }

  Future<Uint8List> _readBounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream.timeout(_requestTimeout)) {
      length += chunk.length;
      if (length > _maxResponseBytes) {
        throw const WeatherFetchException('Weather response is too large');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void close() {
    if (_ownsClient) _httpClient.close();
  }
}

class WeatherFetchException implements Exception {
  const WeatherFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}
