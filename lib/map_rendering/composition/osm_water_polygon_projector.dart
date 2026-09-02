import 'dart:math' as math;
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
  ) => projectRing(feature.ring, projectPoint);

  /// Projects a closed area ring and drops only screen-space detail that
  /// cannot affect the drawn edge. OSM keeps the complete geometry; this is a
  /// transient paint-time optimisation for large lakes and coastal fragments.
  ///
  /// Sharp corners are retained even when their adjacent vertices are close,
  /// so a narrow inlet is not turned into a misleading smooth shore.
  static List<Offset> projectRing(
    List<LatLng> ring,
    Offset Function(LatLng point) projectPoint, {
    double minimumDistancePixels = .75,
  }) {
    if (ring.length < 3) {
      return [for (final point in ring) projectPoint(point)];
    }
    final source = [for (final point in ring) projectPoint(point)];
    if (source.length > 3 && source.first == source.last) {
      source.removeLast();
    }
    if (source.length < 3) return source;

    final projected = <Offset>[];
    for (var index = 0; index < source.length; index++) {
      final previous = source[(index - 1 + source.length) % source.length];
      final point = source[index];
      final next = source[(index + 1) % source.length];
      if (projected.isEmpty ||
          (point - projected.last).distance >= minimumDistancePixels ||
          _isSharpTurn(previous, point, next)) {
        projected.add(point);
      }
    }
    if (projected.length >= 3) return projected;
    return source.take(3).toList(growable: false);
  }

  static bool _isSharpTurn(Offset before, Offset point, Offset after) {
    final incoming = point - before;
    final outgoing = after - point;
    if (incoming.distance == 0 || outgoing.distance == 0) return false;
    final cosine =
        ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
                (incoming.distance * outgoing.distance))
            .clamp(-1.0, 1.0);
    return math.acos(cosine) >= math.pi / 7.2;
  }

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
