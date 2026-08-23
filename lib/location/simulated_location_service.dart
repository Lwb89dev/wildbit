import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../domain/entities/geo_fix.dart';
import 'location_service.dart';

/// Walks a fixed path back and forth at a hiking pace. Used only on
/// desktop/dev builds where no real GPS hardware is available, so Bit and
/// the map can still be exercised end to end. Never used on Android/iOS.
class SimulatedLocationService implements LocationService {
  SimulatedLocationService({required List<LatLng> path, this.metersPerSecond = 1.4})
      : _path = path,
        _segmentLengths = _computeSegmentLengths(path) {
    _totalLength = _segmentLengths.fold(0, (sum, l) => sum + l);
  }

  static const _distance = Distance();

  static List<double> _computeSegmentLengths(List<LatLng> path) {
    return [
      for (var i = 0; i < path.length - 1; i++)
        _distance.as(LengthUnit.Meter, path[i], path[i + 1]),
    ];
  }

  final List<LatLng> _path;
  final List<double> _segmentLengths;
  late final double _totalLength;
  final double metersPerSecond;

  final _controller = StreamController<GeoFix>.broadcast();
  Timer? _timer;
  double _traveled = 0;
  int _direction = 1;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Stream<GeoFix> get positionStream {
    _timer ??= Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    return _controller.stream;
  }

  @override
  Future<GeoFix?> getCurrentPosition() async => _currentPoint();

  GeoFix _currentPoint() {
    var remaining = _traveled;
    for (var i = 0; i < _segmentLengths.length; i++) {
      final length = _segmentLengths[i];
      if (remaining <= length || i == _segmentLengths.length - 1) {
        final t = length == 0 ? 0.0 : (remaining / length).clamp(0.0, 1.0);
        final a = _path[i];
        final b = _path[i + 1];
        final lat = a.latitude + (b.latitude - a.latitude) * t;
        final lng = a.longitude + (b.longitude - a.longitude) * t;
        final forwardBearing = _distance.bearing(a, b);
        final bearing = _direction > 0 ? forwardBearing : (forwardBearing + 180) % 360;
        return GeoFix(
          position: LatLng(lat, lng),
          timestamp: DateTime.now(),
          headingDegrees: bearing < 0 ? bearing + 360 : bearing,
          speedMetersPerSecond: metersPerSecond,
          accuracyMeters: 5,
        );
      }
      remaining -= length;
    }
    return GeoFix(position: _path.first, timestamp: DateTime.now());
  }

  void _tick() {
    final step = metersPerSecond * 0.2;
    _traveled += _direction * step;
    if (_traveled >= _totalLength) {
      _traveled = _totalLength;
      _direction = -1;
    } else if (_traveled <= 0) {
      _traveled = 0;
      _direction = 1;
    }
    _controller.add(_currentPoint());
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
