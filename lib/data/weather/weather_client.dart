import 'dart:async';
import 'dart:convert';

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
        'latitude': position.latitude.toStringAsFixed(4),
        'longitude': position.longitude.toStringAsFixed(4),
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
    final response = await _httpClient
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw WeatherFetchException(
        'Weather service returned ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > _maxResponseBytes) {
      throw const WeatherFetchException('Weather response is too large');
    }
    final decoded = jsonDecode(response.body);
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
