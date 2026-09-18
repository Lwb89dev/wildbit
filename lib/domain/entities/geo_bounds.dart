import 'package:latlong2/latlong.dart';

/// Simple rectangular geographic bounds, kept independent from any map
/// widget/rendering package so the domain layer has no UI dependencies.
class GeoBounds {
  const GeoBounds({required this.southWest, required this.northEast});

  final LatLng southWest;
  final LatLng northEast;

  bool contains(LatLng point) {
    return point.latitude >= southWest.latitude &&
        point.latitude <= northEast.latitude &&
        _longitudeOffset(southWest.longitude, point.longitude) <=
            _longitudeSpan(southWest.longitude, northEast.longitude);
  }

  bool containsBounds(GeoBounds other) {
    if (other.southWest.latitude < southWest.latitude ||
        other.northEast.latitude > northEast.latitude) {
      return false;
    }
    final span = _longitudeSpan(southWest.longitude, northEast.longitude);
    final otherSpan = _longitudeSpan(
      other.southWest.longitude,
      other.northEast.longitude,
    );
    return otherSpan <= span &&
        _longitudeOffset(southWest.longitude, other.southWest.longitude) <=
            span - otherSpan;
  }

  static double _longitudeSpan(double west, double east) {
    final raw = east - west;
    if (raw.abs() >= 360) return 360;
    final wrapped = raw % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }

  static double _longitudeOffset(double west, double longitude) {
    final wrapped = (longitude - west) % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }
}
