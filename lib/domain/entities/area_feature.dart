import 'package:latlong2/latlong.dart';

import '../enums/map_feature_kind.dart';

/// A filled area on the map (forest patch, lake, meadow, ...).
class AreaFeature {
  const AreaFeature({
    required this.kind,
    required this.ring,
    this.holes = const [],
    this.sourceId,
  });

  final MapFeatureKind kind;

  /// Closed polygon ring (first point == last point not required).
  final List<LatLng> ring;

  /// Inner rings of an OSM multipolygon. A normal way has no holes; keeping
  /// them here prevents lakes/islands and forest clearings from being filled
  /// as solid rectangles by the pixel compositor.
  final List<List<LatLng>> holes;

  /// Stable OSM identity when the feature originated from a way. It lets
  /// adjacent cache cells deduplicate the same polygon without comparing
  /// floating-point geometry.
  final String? sourceId;
}
