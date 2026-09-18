import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/sun_calc.dart';
import 'wildbit_theme.dart';

/// Owns the current theme choice and, optionally, an automatic dark-mode
/// switch driven by sunrise/sunset at the hiker's position. Off by default —
/// the theme the user picked is the theme they expect to see until they ask
/// otherwise.
class ThemeProvider extends ChangeNotifier {
  static const _themeKey = 'wildbit.themeId';
  static const _autoDarkKey = 'wildbit.autoDark';

  SharedPreferences? _prefs;
  AppThemeId _current = AppThemeId.light;
  bool _autoDarkEnabled = false;
  bool _autoDarkActive = false;

  double? _lastLat;
  double? _lastLng;
  Timer? _autoDarkTimer;
  bool _disposed = false;
  int _themeWriteGeneration = 0;
  int _autoDarkWriteGeneration = 0;

  AppThemeId get current => _current;
  bool get autoDarkEnabled => _autoDarkEnabled;

  /// Switches to the dark palette when auto-dark is active, regardless of
  /// the user's manual pick — but never overrides an explicit dark choice.
  AppThemeId get effective {
    if (_autoDarkEnabled && _autoDarkActive) return AppThemeId.dark;
    return _current;
  }

  ThemeData get effectiveThemeData => WildBitTheme.build(effective);

  Future<void> init() async {
    final themeGeneration = _themeWriteGeneration;
    final autoDarkGeneration = _autoDarkWriteGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _prefs = prefs;
    if (themeGeneration == _themeWriteGeneration) {
      _current = AppThemeIdExt.fromIndex(prefs.getInt(_themeKey) ?? 0);
    }
    if (autoDarkGeneration == _autoDarkWriteGeneration) {
      _autoDarkEnabled = prefs.getBool(_autoDarkKey) ?? false;
    }
    _notifyListeners();
  }

  void setTheme(AppThemeId id) {
    if (_disposed) return;
    final generation = ++_themeWriteGeneration;
    _current = id;
    unawaited(_persistTheme(id, generation));
    _notifyListeners();
  }

  void setAutoDarkEnabled(bool value) {
    if (_disposed) return;
    final generation = ++_autoDarkWriteGeneration;
    _autoDarkEnabled = value;
    unawaited(_persistAutoDark(value, generation));
    if (!value) {
      _autoDarkTimer?.cancel();
      _autoDarkActive = false;
    } else if (_lastLat != null && _lastLng != null) {
      _recalc(_lastLat!, _lastLng!);
    }
    _notifyListeners();
  }

  /// Feed the latest GPS position. Debounced to ~10 km moves — the sun's
  /// position barely changes over a hike, so there's no need to recompute
  /// on every fix.
  void onPositionUpdate(double lat, double lng) {
    if (_disposed || !_autoDarkEnabled) return;
    final prevLat = _lastLat;
    final prevLng = _lastLng;
    if (prevLat != null && prevLng != null) {
      final dLat = lat - prevLat;
      final dLng = lng - prevLng;
      if (dLat * dLat + dLng * dLng < 0.0081) return;
    }
    _lastLat = lat;
    _lastLng = lng;
    _recalc(lat, lng);
  }

  void _recalc(double lat, double lng) {
    _autoDarkTimer?.cancel();
    final now = DateTime.now().toUtc();
    final times = SunCalc.sunTimes(lat, lng, now);

    bool active;
    DateTime nextTransition;
    if (times.rise == null || times.set == null) {
      final doy = now.difference(DateTime.utc(now.year, 1, 1)).inDays;
      active = lat > 0 ? doy > 355 || doy < 80 : doy > 80 && doy < 355;
      nextTransition = now.add(const Duration(hours: 24));
    } else if (now.isBefore(times.rise!) || now.isAfter(times.set!)) {
      active = true;
      nextTransition = now.isBefore(times.rise!)
          ? times.rise!
          : _tomorrowSunrise(lat, lng, now);
    } else {
      active = false;
      nextTransition = times.set!;
    }

    final changed = active != _autoDarkActive;
    _autoDarkActive = active;
    if (changed) _notifyListeners();

    const minDelay = Duration(seconds: 1);
    final delay = nextTransition.difference(now);
    _autoDarkTimer = Timer(
      delay < minDelay ? minDelay : delay,
      () => _recalc(lat, lng),
    );
  }

  DateTime _tomorrowSunrise(double lat, double lng, DateTime now) {
    final tomorrow = now.add(const Duration(days: 1));
    final times = SunCalc.sunTimes(lat, lng, tomorrow);
    return times.rise ?? now.add(const Duration(hours: 24));
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persistTheme(AppThemeId id, int generation) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (_disposed || generation != _themeWriteGeneration) return;
    _prefs = prefs;
    await prefs.setInt(_themeKey, AppThemeId.values.indexOf(id));
  }

  Future<void> _persistAutoDark(bool value, int generation) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (_disposed || generation != _autoDarkWriteGeneration) return;
    _prefs = prefs;
    await prefs.setBool(_autoDarkKey, value);
  }

  @override
  void dispose() {
    _disposed = true;
    _autoDarkTimer?.cancel();
    super.dispose();
  }
}
