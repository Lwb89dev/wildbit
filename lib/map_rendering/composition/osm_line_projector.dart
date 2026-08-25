import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../domain/entities/line_feature.dart';

/// Short-lived cache shared by route geometry and route labels for one camera
/// view. A camera change invalidates the view; different OSM ways remain
/// independently keyed by their stable geometry seed and LOD parameters.
class ProjectedLineCache {
  ProjectedLineCache({this.maxEntries = 2048});

  final int maxEntries;
  String? _viewKey;
  final _entries = <String, List<Offset>>{};

  void beginView(String viewKey) {
    if (_viewKey == viewKey) return;
    _viewKey = viewKey;
    _entries.clear();
  }

  List<Offset> project(
    LineFeature feature,
    Offset Function(LatLng point) projectPoint, {
    required double minimumDistancePixels,
    required int maximumPoints,
  }) {
    final key =
        '${OsmLineProjector.seedFor(feature)}:'
        '${minimumDistancePixels.toStringAsFixed(2)}:$maximumPoints';
    final cached = _entries[key];
    if (cached != null) return cached;
    final points = OsmLineProjector.projectSimplified(
      feature,
      projectPoint,
      minimumDistancePixels: minimumDistancePixels,
      maximumPoints: maximumPoints,
    );
    if (_entries.length >= maxEntries && _entries.isNotEmpty) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = points;
    return points;
  }

  int get length => _entries.length;
}

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
    int? maximumPoints,
  }) {
    return projectSimplifiedPoints(
      feature.points,
      projectPoint,
      minimumDistancePixels: minimumDistancePixels,
      maximumPoints: maximumPoints,
    );
  }

  static List<Offset> projectSimplifiedPoints(
    List<LatLng> points,
    Offset Function(LatLng point) projectPoint, {
    required double minimumDistancePixels,
    int? maximumPoints,
  }) {
    if (points.length < 3) {
      return [for (final point in points) projectPoint(point)];
    }
    final source = [for (final point in points) projectPoint(point)];
    final projected = <Offset>[source.first];
    for (var index = 1; index + 1 < source.length; index++) {
      final offset = source[index];
      if ((offset - projected.last).distance >= minimumDistancePixels ||
          _isSharpTurn(source[index - 1], offset, source[index + 1])) {
        projected.add(offset);
      }
    }
    projected.add(source.last);
    return maximumPoints == null
        ? projected
        : capPoints(projected, maximumPoints: maximumPoints);
  }

  /// Caps only pathological OSM ways at overview zooms. Endpoints remain
  /// exact, so a long mapped path cannot be silently removed from the scene.
  static List<Offset> capPoints(
    List<Offset> points, {
    required int maximumPoints,
  }) {
    if (maximumPoints < 2 || points.length <= maximumPoints) {
      return points;
    }
    final result = <Offset>[points.first];
    final span = points.length - 1;
    for (var index = 1; index < maximumPoints - 1; index++) {
      final sourceIndex = ((index * span) / (maximumPoints - 1)).round();
      if (sourceIndex > 0 && sourceIndex < points.length - 1) {
        result.add(points[sourceIndex]);
      }
    }
    result.add(points.last);
    return result;
  }

  static bool overlapsViewport(
    List<Offset> points,
    Size viewport, {
    double margin = 24,
  }) {
    if (points.isEmpty || viewport.isEmpty) return false;
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return right >= -margin &&
        left <= viewport.width + margin &&
        bottom >= -margin &&
        top <= viewport.height + margin;
  }

  static bool _isSharpTurn(Offset before, Offset point, Offset after) {
    final incoming = point - before;
    final outgoing = after - point;
    if (incoming.distance == 0 || outgoing.distance == 0) return false;
    final cosine =
        ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
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
