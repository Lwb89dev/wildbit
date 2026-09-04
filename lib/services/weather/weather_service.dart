import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../data/weather/weather_client.dart';
import '../../domain/entities/weather_snapshot.dart';

/// Fetches weather for the current map area without tying GPS to networking.
/// A rounded cell and a 30-minute TTL prevent a GPS stream from becoming a
/// network poller while still following a hiker who changes area.
class WeatherService extends ChangeNotifier {
  WeatherService({WeatherClient? client, DateTime Function()? now})
    : _client = client ?? OpenMeteoClient(),
      _ownedClient = client == null,
      _now = now ?? DateTime.now;

  static const refreshInterval = Duration(minutes: 30);

  final WeatherClient _client;
  final bool _ownedClient;
  final DateTime Function() _now;

  WeatherSnapshot? _snapshot;
  String? _lastCell;
  DateTime? _lastAttempt;
  Future<void>? _request;
  bool _loading = false;
  Object? _lastError;

  WeatherSnapshot? get snapshot => _snapshot;
  bool get isLoading => _loading;
  Object? get lastError => _lastError;

  Future<void> refresh(LatLng position) {
    final cell = _cellKey(position);
    final lastAttempt = _lastAttempt;
    if (_request != null ||
        (cell == _lastCell &&
            lastAttempt != null &&
            _now().difference(lastAttempt) < refreshInterval)) {
      return _request ?? Future<void>.value();
    }

    _lastCell = cell;
    _lastAttempt = _now();
    _loading = true;
    _lastError = null;
    notifyListeners();
    final request = _client
        .fetchCurrent(position)
        .then((snapshot) {
          _snapshot = snapshot;
          _lastError = null;
        })
        .catchError((Object error) {
          // Existing weather remains useful offline. The overlay simply keeps its
          // last stable state instead of flashing to a default atmosphere.
          _lastError = error;
        })
        .whenComplete(() {
          _loading = false;
          _request = null;
          notifyListeners();
        });
    _request = request;
    return request;
  }

  void clear() {
    _snapshot = null;
    _lastCell = null;
    _lastAttempt = null;
    _lastError = null;
    notifyListeners();
  }

  static String _cellKey(LatLng position) =>
      '${position.latitude.toStringAsFixed(1)}:${position.longitude.toStringAsFixed(1)}';

  @override
  void dispose() {
    if (_ownedClient) {
      (_client as OpenMeteoClient).close();
    }
    super.dispose();
  }
}
