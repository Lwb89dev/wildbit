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
        point.longitude >= southWest.longitude &&
        point.longitude <= northEast.longitude;
  }

  bool containsBounds(GeoBounds other) =>
      contains(other.southWest) && contains(other.northEast);
}
