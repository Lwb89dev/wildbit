import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Tilt-compensated compass heading from the raw accelerometer +
/// magnetometer, smoothed with a low-pass filter and throttled to ~10 Hz so
/// UI/map updates stay smooth instead of chasing every noisy sample.
///
/// This deliberately does not do what a turn-by-turn driving app needs
/// (course-over-ground from GPS, road-snap rejection, route-aware easing —
/// see Roadstr's `HeadingFilter`): a hiking map only needs "which way is the
/// phone pointing right now", which the magnetometer alone answers.
class CompassHeadingService {
  static const _smoothing = 0.15;
  static const _updateInterval = Duration(milliseconds: 100);

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magnetSub;
  AccelerometerEvent? _lastAccel;
  double _heading = 0;
  int _lastEmitMs = 0;

  final _controller = StreamController<double>.broadcast(
    onListen: () {},
    onCancel: () {},
  );

  /// Degrees, 0 = north, clockwise. Emits at most every [_updateInterval].
  /// Listening alone does not turn the sensors on — call [start] when the
  /// heading is actually needed (and [stop] the moment it isn't), so the
  /// accelerometer/magnetometer never sample while the app is backgrounded
  /// or the feature is off.
  Stream<double> get headingStream => _controller.stream;

  void start() {
    if (_accelSub != null) return;
    // sensors_plus has no Linux/Windows/macOS implementation: it reports the
    // missing platform channel as an *unhandled* async error (not delivered
    // through the stream's own error channel), so no try/catch or `onError`
    // here can intercept it. Simplest correct fix is to never touch the
    // plugin outside the platforms it actually supports — the compass is an
    // optional enhancement, headingStream just never emits elsewhere.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _accelSub = accelerometerEventStream().listen(
      (e) => _lastAccel = e,
      onError: (Object _) {},
      cancelOnError: false,
    );
    _magnetSub = magnetometerEventStream().listen(
      _onMagnetometerEvent,
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _onMagnetometerEvent(MagnetometerEvent mag) {
    final accel = _lastAccel;
    if (accel == null) return;
    final azimuth = _tiltCompensatedAzimuth(accel, mag);
    if (!azimuth.isFinite) return;

    var diff = azimuth - _heading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _heading = (_heading + diff * _smoothing) % 360;
    if (_heading < 0) _heading += 360;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastEmitMs < _updateInterval.inMilliseconds) return;
    _lastEmitMs = now;
    _controller.add(_heading);
  }

  /// Azimuth of the phone's -Z axis (the back of the phone, i.e. the
  /// direction the user is facing while looking at the screen in portrait).
  /// 0 = north, 90 = east, clockwise. Returns NaN if the device is close to
  /// free-fall or the field readings are degenerate.
  double _tiltCompensatedAzimuth(AccelerometerEvent accel, MagnetometerEvent mag) {
    // sensors_plus reports the accelerometer's reaction force; negate for
    // the actual gravity vector.
    var gx = -accel.x, gy = -accel.y, gz = -accel.z;
    final gravityNorm = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gravityNorm < 0.1) return double.nan;
    gx /= gravityNorm;
    gy /= gravityNorm;
    gz /= gravityNorm;

    var ex = gy * mag.z - gz * mag.y;
    var ey = gz * mag.x - gx * mag.z;
    var ez = gx * mag.y - gy * mag.x;
    final eastNorm = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (eastNorm < 0.1) return double.nan;
    ex /= eastNorm;
    ey /= eastNorm;
    ez /= eastNorm;

    final northZ = ex * gy - ey * gx;
    var azimuth = math.atan2(-ez, -northZ) * 180 / math.pi;
    if (azimuth < 0) azimuth += 360;
    return azimuth;
  }

  /// Stops sampling without closing [headingStream]'s controller, so a
  /// caller can [start] it again later (e.g. when the app returns to the
  /// foreground) without needing a fresh subscription.
  void stop() {
    _accelSub?.cancel();
    _magnetSub?.cancel();
    _accelSub = null;
    _magnetSub = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
