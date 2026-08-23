import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../domain/entities/line_feature.dart';

/// Projection adapter for OSM-derived linear features (paths and roads).
abstract final class OsmLineProjector {
  static List<Offset> project(
    LineFeature feature,
    Offset Function(LatLng point) projectPoint,
  ) => [for (final point in feature.points) projectPoint(point)];

  /// Drops points too close to change the visible pixel path. Source OSM
  /// geometry remains untouched; this is paint-time level-of-detail only.
  static List<Offset> projectSimplified(
    LineFeature feature,
    Offset Function(LatLng point) projectPoint, {
    required double minimumDistancePixels,
  }) {
    if (feature.points.length < 3) return project(feature, projectPoint);
    final source = project(feature, projectPoint);
    final projected = <Offset>[source.first];
    for (var index = 1; index + 1 < source.length; index++) {
      final offset = source[index];
      if ((offset - projected.last).distance >= minimumDistancePixels ||
          _isSharpTurn(source[index - 1], offset, source[index + 1])) {
        projected.add(offset);
      }
    }
    projected.add(source.last);
    return projected;
  }

  static bool _isSharpTurn(Offset before, Offset point, Offset after) {
    final incoming = point - before;
    final outgoing = after - point;
    if (incoming.distance == 0 || outgoing.distance == 0) return false;
    final cosine = ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
            (incoming.distance * outgoing.distance))
        .clamp(-1.0, 1.0);
    final turn = math.acos(cosine);
    return turn >= math.pi / 7.2; // Preserve turns of 25 degrees or more.
  }

  static int seedFor(LineFeature feature) {
    var seed = 23;
    for (final point in feature.points) {
      seed = seed * 31 + (point.latitude * 1e5).round();
      seed = seed * 31 + (point.longitude * 1e5).round();
    }
    return seed;
  }
}
