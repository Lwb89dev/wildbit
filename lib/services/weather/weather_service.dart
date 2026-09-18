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
  static const failureRetryInterval = Duration(minutes: 2);

  final WeatherClient _client;
  final bool _ownedClient;
  final DateTime Function() _now;

  WeatherSnapshot? _snapshot;
  String? _lastCell;
  DateTime? _lastAttempt;
  Future<void>? _request;
  LatLng? _pendingPosition;
  bool _loading = false;
  Object? _lastError;
  bool _disposed = false;
  int _generation = 0;

  WeatherSnapshot? get snapshot => _snapshot;
  bool get isLoading => _loading;
  Object? get lastError => _lastError;

  Future<void> refresh(LatLng position) {
    if (_disposed) return Future<void>.value();
    final cell = _cellKey(position);
    final lastAttempt = _lastAttempt;
    final activeRequest = _request;
    if (activeRequest != null) {
      if (cell != _lastCell) _pendingPosition = position;
      return activeRequest;
    }
    final retryInterval = _lastError == null
        ? refreshInterval
        : failureRetryInterval;
    if (cell == _lastCell &&
        lastAttempt != null &&
        _now().difference(lastAttempt) < retryInterval) {
      return Future<void>.value();
    }

    _lastCell = cell;
    _lastAttempt = _now();
    _loading = true;
    _lastError = null;
    _notifyListeners();
    final generation = ++_generation;
    final request = _client
        .fetchCurrent(position)
        .then((snapshot) {
          if (_disposed || generation != _generation) return;
          _snapshot = snapshot;
          _lastError = null;
        })
        .catchError((Object error) {
          if (_disposed || generation != _generation) return;
          // Existing weather remains useful offline. The overlay simply keeps its
          // last stable state instead of flashing to a default atmosphere.
          _lastError = error;
        })
        .whenComplete(() {
          _loading = false;
          _request = null;
          _notifyListeners();
          final pending = _pendingPosition;
          _pendingPosition = null;
          if (pending != null && !_disposed) unawaited(refresh(pending));
        });
    _request = request;
    return request;
  }

  void clear() {
    _generation++;
    _snapshot = null;
    _lastCell = null;
    _lastAttempt = null;
    _lastError = null;
    _pendingPosition = null;
    _notifyListeners();
  }

  static String _cellKey(LatLng position) =>
      '${position.latitude.toStringAsFixed(1)}:${position.longitude.toStringAsFixed(1)}';

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pendingPosition = null;
    if (_ownedClient) {
      (_client as OpenMeteoClient).close();
    }
    super.dispose();
  }
}
