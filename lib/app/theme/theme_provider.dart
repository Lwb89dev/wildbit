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
    _prefs = await SharedPreferences.getInstance();
    _current = AppThemeIdExt.fromIndex(_prefs?.getInt(_themeKey) ?? 0);
    _autoDarkEnabled = _prefs?.getBool(_autoDarkKey) ?? false;
    notifyListeners();
  }

  void setTheme(AppThemeId id) {
    _current = id;
    _prefs?.setInt(_themeKey, AppThemeId.values.indexOf(id));
    notifyListeners();
  }

  void setAutoDarkEnabled(bool value) {
    _autoDarkEnabled = value;
    _prefs?.setBool(_autoDarkKey, value);
    if (!value) {
      _autoDarkTimer?.cancel();
      _autoDarkActive = false;
    } else if (_lastLat != null && _lastLng != null) {
      _recalc(_lastLat!, _lastLng!);
    }
    notifyListeners();
  }

  /// Feed the latest GPS position. Debounced to ~10 km moves — the sun's
  /// position barely changes over a hike, so there's no need to recompute
  /// on every fix.
  void onPositionUpdate(double lat, double lng) {
    if (!_autoDarkEnabled) return;
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
      nextTransition = now.isBefore(times.rise!) ? times.rise! : _tomorrowSunrise(lat, lng, now);
    } else {
      active = false;
      nextTransition = times.set!;
    }

    final changed = active != _autoDarkActive;
    _autoDarkActive = active;
    if (changed) notifyListeners();

    const minDelay = Duration(seconds: 1);
    final delay = nextTransition.difference(now);
    _autoDarkTimer = Timer(delay < minDelay ? minDelay : delay, () => _recalc(lat, lng));
  }

  DateTime _tomorrowSunrise(double lat, double lng, DateTime now) {
    final tomorrow = now.add(const Duration(days: 1));
    final times = SunCalc.sunTimes(lat, lng, tomorrow);
    return times.rise ?? now.add(const Duration(hours: 24));
  }

  @override
  void dispose() {
    _autoDarkTimer?.cancel();
    super.dispose();
  }
}
