import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';

/// Converts the geographic ring emitted by the OSM parser into the current
/// map viewport's logical pixel coordinates. Keeping this adapter separate
/// makes the pixel compositor independent from flutter_map and reusable by
/// offline chunk rendering.
abstract final class OsmWaterPolygonProjector {
  static List<Offset> project(
    AreaFeature feature,
    Offset Function(LatLng point) projectPoint,
  ) => [for (final point in feature.ring) projectPoint(point)];

  /// A stable geometry-derived seed keeps tile variants unchanged when the
  /// viewport repaints or is revisited offline.
  static int seedFor(AreaFeature feature) {
    var seed = 17;
    for (final point in feature.ring) {
      seed = 31 * seed + (point.latitude * 1e5).round();
      seed = 31 * seed + (point.longitude * 1e5).round();
    }
    return seed;
  }
}
