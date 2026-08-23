import 'package:latlong2/latlong.dart';

import '../enums/map_feature_kind.dart';
import 'route_metadata.dart';

/// A linear feature on the map (trail, road, contour line, ...).
class LineFeature {
  const LineFeature({
    required this.kind,
    required this.points,
    this.name,
    this.metadata = const RouteMetadata(),
    this.nodeIds = const [],
  });

  final MapFeatureKind kind;
  final List<LatLng> points;
  final String? name;
  final RouteMetadata metadata;

  /// Ordered OSM node references that define this way.
  ///
  /// These identifiers, not a proximity comparison of latitude/longitude,
  /// are the only admissible source of connectivity in the route graph.
  /// An empty list means the topology is unknown.
  final List<String> nodeIds;
}
