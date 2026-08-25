import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../domain/entities/geo_fix.dart';
import 'location_service.dart';

/// Real device GPS via `geolocator`. This is what ships on Android/iOS.
class GeolocatorLocationService implements LocationService {
  static const _gnssChannel = MethodChannel('app.wildbit/gnss');

  static final _settings = Platform.isAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 500),
          forceLocationManager: true,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'WildBit',
            notificationText: 'GPS attivo',
            enableWakeLock: false,
          ),
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 2,
        );

  GeoFix? _latestFix;
  bool _assistancePrimed = false;

  @override
  Future<bool> ensurePermission() async {
    // Do not call Geolocator.isLocationServiceEnabled() on Android: the
    // plugin may select FusedLocationClient and invoke Google Play Services.
    // The native channel checks the platform LocationManager directly.
    if (Platform.isAndroid) {
      // This is diagnostic only: some Android devices report provider state
      // late after permission/settings changes. Do not block permission or a
      // direct GNSS request on that advisory check.
      try {
        final enabled = await _gnssChannel
            .invokeMethod<bool>('isLocationEnabled')
            .timeout(const Duration(seconds: 2));
        if (enabled == false) return false;
      } on PlatformException {
        // The native channel is optional; LocationManager remains the source.
      } on TimeoutException {
        // A stalled optional channel must never hold up the permission flow.
      } on MissingPluginException {
        // Desktop/test engines do not expose the Android channel.
      }
    } else if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<GeoFix> get positionStream {
    unawaited(_primeAssistanceData());
    return Geolocator.getPositionStream(
      locationSettings: _settings,
    ).map(_toGeoFix).where((fix) => fix != null).cast<GeoFix>();
  }

  @override
  Future<GeoFix?> getCurrentPosition() async {
    // Keep this diagnostic visible in adb logcat; it distinguishes a cold
    // GNSS lock from a permission/channel failure without invoking Google APIs.
    debugPrint('WildBit GNSS: richiesta posizione corrente');
    if (!await ensurePermission()) return null;
    // Roadstr's no-Google strategy: return Android's LocationManager cache
    // immediately so recenter/search never wait for a cold satellite lock.
    if (Platform.isAndroid) {
      try {
        final raw = await _gnssChannel
            .invokeMethod<Map>('lastKnownLocation')
            .timeout(const Duration(seconds: 2));
        debugPrint('WildBit GNSS: cache nativa=${raw != null}');
        final nativeFix = _fromNativeLocation(raw);
        if (nativeFix != null) {
          debugPrint(
            'WildBit GNSS: posizione nativa ottenuta '
            '(accuracy=${nativeFix.accuracyMeters}m)',
          );
          return nativeFix;
        }
      } on PlatformException catch (error) {
        debugPrint('WildBit GNSS: canale nativo $error');
        // Fall through to the plugin's LocationManager-backed path.
      } on MissingPluginException {
        // Fall through to geolocator on engines without the optional channel.
      } on TimeoutException {
        debugPrint('WildBit GNSS: canale nativo in timeout');
      }
    }
    final lastKnown = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: Platform.isAndroid,
    ).timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (lastKnown != null) return _toGeoFix(lastKnown);
    if (_latestFix != null) return _latestFix;

    // A first run has no Android cache yet.  Ask the same platform
    // LocationManager source for one fresh GNSS fix; without this, Explore
    // and the centre button immediately gave up before permission/GPS had a
    // chance to produce their first result.
    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: _singleFixSettings,
      );
      debugPrint('WildBit GNSS: fix fresco ottenuto (accuracy=${fresh.accuracy}m)');
      return _toGeoFix(fresh);
    } on TimeoutException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } on PermissionDeniedException {
      debugPrint('WildBit GNSS: permesso negato');
      return null;
    }
  }

  GeoFix? _fromNativeLocation(Map? raw) {
    if (raw == null) return null;
    final latitude = (raw['latitude'] as num?)?.toDouble();
    final longitude = (raw['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return _toGeoFixValues(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (raw['timestamp'] as num?)?.toInt() ?? 0,
      ),
      accuracy: (raw['accuracy'] as num?)?.toDouble() ?? 999,
      altitude: (raw['altitude'] as num?)?.toDouble() ?? 0,
      bearing: (raw['bearing'] as num?)?.toDouble() ?? -1,
      speed: (raw['speed'] as num?)?.toDouble() ?? 0,
    );
  }

  GeoFix? _toGeoFixValues({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double accuracy,
    required double altitude,
    required double bearing,
    required double speed,
  }) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    final fix = GeoFix(
      position: LatLng(latitude, longitude),
      timestamp: timestamp,
      altitudeMeters: altitude,
      accuracyMeters: accuracy,
      headingDegrees: bearing >= 0 ? bearing : null,
      speedMetersPerSecond: speed < 0 ? 0 : speed,
    );
    _latestFix = fix;
    return fix;
  }

  static final _singleFixSettings = Platform.isAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 20),
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        );

  GeoFix? _toGeoFix(Position position) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      return null;
    }
    final fix = GeoFix(
      position: LatLng(position.latitude, position.longitude),
      timestamp: position.timestamp,
      altitudeMeters: position.altitude,
      accuracyMeters: position.accuracy,
      headingDegrees: position.heading >= 0 ? position.heading : null,
      speedMetersPerSecond: position.speed < 0 ? 0 : position.speed,
    );
    _latestFix = fix;
    return fix;
  }

  Future<void> _primeAssistanceData() async {
    if (_assistancePrimed || !Platform.isAndroid) return;
    _assistancePrimed = true;
    try {
      await _gnssChannel.invokeMethod<bool>('primeAssistanceData');
    } catch (_) {
      // Optional Android GNSS extension; raw GNSS continues without it.
    }
  }
}
