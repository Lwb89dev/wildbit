import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../domain/entities/geo_bounds.dart';

/// A small deterministic preset around a GPS fix. It is intentionally bounded
/// so a user cannot accidentally queue an entire province from one button.
class OfflineRegionPackage {
  const OfflineRegionPackage({
    required this.name,
    required this.bounds,
  });

  final String name;
  final GeoBounds bounds;

  factory OfflineRegionPackage.local(LatLng center, {double radiusKm = 1}) {
    final latDelta = radiusKm / 111.32;
    final lngDelta = radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180));
    return OfflineRegionPackage(
      name: 'Pacchetto locale (${radiusKm.toStringAsFixed(0)} km)',
      bounds: GeoBounds(
        southWest: LatLng(
          center.latitude - latDelta,
          center.longitude - lngDelta,
        ),
        northEast: LatLng(
          center.latitude + latDelta,
          center.longitude + lngDelta,
        ),
      ),
    );
  }

}
