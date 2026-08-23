import 'package:latlong2/latlong.dart';

/// A single timestamped GPS fix, independent of any specific location
/// provider (device GPS, imported GPX, simulated desktop position, ...).
class GeoFix {
  const GeoFix({
    required this.position,
    required this.timestamp,
    this.altitudeMeters,
    this.accuracyMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
  });

  final LatLng position;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
}
