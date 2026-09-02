import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';

/// Short-lived cache shared by route geometry and route labels for one camera
/// view. A camera change invalidates the view; different OSM ways remain
/// independently keyed by their stable geometry seed and LOD parameters.
class ProjectedLineCache {
  ProjectedLineCache({this.maxEntries = 2048});

  final int maxEntries;
  String? _viewKey;
  final _entries = <String, List<Offset>>{};
  int _hits = 0;
  int _misses = 0;

  /// Number of projections served from the in-memory camera cache.
  int get hits => _hits;

  /// Number of projections that had to simplify and project the source way.
  int get misses => _misses;

  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0 : _hits / total;
  }

  void beginView(String viewKey) {
    if (_viewKey == viewKey) return;
    _viewKey = viewKey;
    _entries.clear();
  }

  /// Drops only screen-space work. Source OSM geometry remains owned by the
  /// map data cache and can be projected again on demand after an Android
  /// memory-pressure callback.
  void clearTransient() {
    _viewKey = null;
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
    if (cached != null) {
      _hits++;
      return cached;
    }
    _misses++;
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
  static final Expando<int> _featureSeeds = Expando<int>(
    'wildbit-line-geometry-seed',
  );
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
      important:
          feature.kind == MapFeatureKind.trail &&
          (feature.metadata.ref != null ||
              feature.metadata.hikingRoutes.isNotEmpty),
    );
  }

  static List<Offset> projectSimplifiedPoints(
    List<LatLng> points,
    Offset Function(LatLng point) projectPoint, {
    required double minimumDistancePixels,
    int? maximumPoints,
    bool important = false,
  }) {
    if (points.length < 3) {
      return [for (final point in points) projectPoint(point)];
    }
    // A few imported OSM ways contain tens of thousands of almost collinear
    // survey vertices. Projecting every one before applying the final LOD
    // cap wastes CPU and allocations. Keep extra samples for important
    // hiking ways, and preserve geographic corners while reducing only this
    // paint-time working set.
    final sourcePoints = maximumPoints == null
        ? points
        : _preSample(
            points,
            maximumPoints: maximumPoints,
            important: important,
          );
    final source = [for (final point in sourcePoints) projectPoint(point)];
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

  static List<LatLng> _preSample(
    List<LatLng> points, {
    required int maximumPoints,
    required bool important,
  }) {
    final sourceLimit = important
        ? math.max(maximumPoints * 16, 4096)
        : math.max(maximumPoints * 4, 1024);
    if (points.length <= sourceLimit) return points;
    final stride = (points.length / sourceLimit).ceil();
    final result = <LatLng>[points.first];
    for (var index = 1; index + 1 < points.length; index++) {
      if (index % stride == 0 ||
          _isSharpGeographicTurn(
            points[index - 1],
            points[index],
            points[index + 1],
          )) {
        result.add(points[index]);
      }
    }
    result.add(points.last);
    return result;
  }

  static bool _isSharpGeographicTurn(
    LatLng before,
    LatLng point,
    LatLng after,
  ) {
    final incoming = Offset(
      point.longitude - before.longitude,
      point.latitude - before.latitude,
    );
    final outgoing = Offset(
      after.longitude - point.longitude,
      after.latitude - point.latitude,
    );
    if (incoming.distance == 0 || outgoing.distance == 0) return false;
    final cosine =
        ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
                (incoming.distance * outgoing.distance))
            .clamp(-1.0, 1.0);
    return math.acos(cosine) >= math.pi / 7.2;
  }

  /// Caps only pathological OSM ways at overview zooms. Endpoints remain
  /// exact, so a long mapped path cannot be silently removed from the scene.
  ///
  /// The former uniform sampling was fast but could discard a sharp switchback
  /// after it had survived projection simplification. Retain the sharpest
  /// visible turns first, then distribute the remaining samples evenly. This
  /// is still paint-only LOD: source OSM points and routing stay untouched.
  static List<Offset> capPoints(
    List<Offset> points, {
    required int maximumPoints,
  }) {
    if (maximumPoints < 2 || points.length <= maximumPoints) {
      return points;
    }
    final slotCount = maximumPoints - 2;
    final sharpTurns = <({int index, double turn})>[];
    for (var index = 1; index + 1 < points.length; index++) {
      final turn = _turnRadians(
        points[index - 1],
        points[index],
        points[index + 1],
      );
      if (turn >= math.pi / 7.2) {
        sharpTurns.add((index: index, turn: turn));
      }
    }
    // When a pathological line has more sharp turns than its current visual
    // cap, the strongest bends win deterministically. Normal hiking routes
    // have a substantially higher cap and retain all of their bends.
    sharpTurns.sort((a, b) {
      final turn = b.turn.compareTo(a.turn);
      return turn != 0 ? turn : a.index.compareTo(b.index);
    });
    final selected = <int>{0, points.length - 1};
    for (final turn in sharpTurns.take(slotCount)) {
      selected.add(turn.index);
    }

    final remainingSlots = maximumPoints - selected.length;
    if (remainingSlots > 0) {
      final available = [
        for (var index = 1; index + 1 < points.length; index++)
          if (!selected.contains(index)) index,
      ];
      // Choose evenly from the ordinary samples left after retaining bends.
      // Indexing the filtered list avoids a quadratic nearest-neighbour scan
      // for very long imported survey ways.
      for (var slot = 1; slot <= remainingSlots; slot++) {
        final availableIndex = (slot * available.length / (remainingSlots + 1))
            .floor();
        selected.add(available[availableIndex]);
      }
    }
    final ordered = selected.toList()..sort();
    return [for (final index in ordered) points[index]];
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
    return _turnRadians(before, point, after) >= math.pi / 7.2;
  }

  static double _turnRadians(Offset before, Offset point, Offset after) {
    final incoming = point - before;
    final outgoing = after - point;
    if (incoming.distance == 0 || outgoing.distance == 0) return 0;
    final cosine =
        ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
                (incoming.distance * outgoing.distance))
            .clamp(-1.0, 1.0);
    return math.acos(cosine);
  }

  static int seedFor(LineFeature feature) {
    final cached = _featureSeeds[feature];
    if (cached != null) return cached;
    var seed = 23;
    for (final point in feature.points) {
      seed = seed * 31 + (point.latitude * 1e5).round();
      seed = seed * 31 + (point.longitude * 1e5).round();
    }
    _featureSeeds[feature] = seed;
    return seed;
  }
}
