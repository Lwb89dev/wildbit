import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/weather/weather_client.dart';
import 'package:wildbit/domain/entities/weather_snapshot.dart';
import 'package:wildbit/services/weather/weather_service.dart';

void main() {
  test('Open-Meteo client parses current conditions', () async {
    final client = OpenMeteoClient(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        body: jsonEncode({
          'current': {
            'temperature_2m': 12.5,
            'precipitation': 2.4,
            'rain': 2.4,
            'snowfall': 0,
            'cloud_cover': 80,
            'visibility': 4200,
            'weather_code': 63,
            'wind_speed_10m': 18,
            'wind_direction_10m': 225,
            'is_day': 1,
          },
        }),
      ),
    );

    final snapshot = await client.fetchCurrent(const LatLng(44.4, 8.9));

    expect(snapshot.temperatureCelsius, 12.5);
    expect(snapshot.precipitationMm, 2.4);
    expect(snapshot.cloudCoverPercent, 80);
    expect(snapshot.isRain, isTrue);
    expect(snapshot.isDay, isTrue);
    expect(snapshot.fogIntensity, closeTo(1 - 4200 / 9000, .0001));
  });

  test('Open-Meteo client rejects unsuccessful responses', () async {
    final client = OpenMeteoClient(
      httpClient: _FakeHttpClient(statusCode: 503, body: ''),
    );

    expect(
      () => client.fetchCurrent(const LatLng(44.4, 8.9)),
      throwsA(isA<WeatherFetchException>()),
    );
  });

  test('weather service deduplicates a cell within its refresh TTL', () async {
    var now = DateTime(2026, 1, 1, 12);
    final fake = _FakeWeatherClient(_snapshot(now));
    final service = WeatherService(client: fake, now: () => now);

    await service.refresh(const LatLng(44.401, 8.901));
    await service.refresh(const LatLng(44.404, 8.904));

    expect(fake.calls, 1);
    expect(service.snapshot, isNotNull);

    now = now.add(const Duration(minutes: 31));
    await service.refresh(const LatLng(44.404, 8.904));
    expect(fake.calls, 2);
  });

  test('weather service keeps the last snapshot when refresh fails', () async {
    var now = DateTime(2026, 1, 1, 12);
    final fake = _FakeWeatherClient(_snapshot(now));
    final service = WeatherService(client: fake, now: () => now);

    await service.refresh(const LatLng(44.4, 8.9));
    final previous = service.snapshot;
    fake.error = const WeatherFetchException('offline');
    now = now.add(const Duration(minutes: 31));
    await service.refresh(const LatLng(44.4, 8.9));

    expect(service.snapshot, same(previous));
    expect(service.lastError, isA<WeatherFetchException>());
  });
}

WeatherSnapshot _snapshot(DateTime fetchedAt) => WeatherSnapshot(
  latitude: 44.4,
  longitude: 8.9,
  fetchedAt: fetchedAt,
  weatherCode: 0,
  temperatureCelsius: 18,
  precipitationMm: 0,
  rainMm: 0,
  snowfallCm: 0,
  cloudCoverPercent: 10,
  visibilityMeters: double.infinity,
  windSpeedKmh: 4,
  windDirectionDegrees: 180,
  isDay: true,
);

class _FakeWeatherClient implements WeatherClient {
  _FakeWeatherClient(this.value);

  final WeatherSnapshot value;
  Object? error;
  int calls = 0;

  @override
  Future<WeatherSnapshot> fetchCurrent(LatLng position) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return value;
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        statusCode,
        request: request,
      );
}
