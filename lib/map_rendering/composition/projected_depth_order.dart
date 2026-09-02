import 'dart:ui';

/// Draw slices around a mobile scene actor.
enum ProjectedDepthSlice { all, behindPivot, inFrontOfPivot }

/// Classifies ground anchors after the map camera has projected and rotated
/// them. Screen Y, rather than latitude, keeps the ordering correct at every
/// map bearing.
abstract final class ProjectedDepthOrder {
  /// Stable back-to-front ordering for ground anchors after camera
  /// projection. Screen Y is the actual visual depth at every bearing; X and
  /// [firstTieBreaker]/[secondTieBreaker] only make equal-depth objects
  /// deterministic across rebuilds.
  static int compare({
    required Offset firstFoot,
    required Offset secondFoot,
    int firstTieBreaker = 0,
    int secondTieBreaker = 0,
  }) {
    final depth = firstFoot.dy.compareTo(secondFoot.dy);
    if (depth != 0) return depth;
    final horizontal = firstFoot.dx.compareTo(secondFoot.dx);
    if (horizontal != 0) return horizontal;
    return firstTieBreaker.compareTo(secondTieBreaker);
  }

  /// Returns the screen-space ground contact of a projected footprint.
  ///
  /// A geographic centroid is not a valid depth anchor after rotation. The
  /// lowest projected vertices are where a building visually meets the
  /// terrain, so their average X with the maximum Y is stable for every map
  /// bearing and for flat-bottomed footprints.
  static Offset footprintAnchor(Iterable<Offset> points) {
    final projected = points.toList(growable: false);
    if (projected.isEmpty) return Offset.zero;
    var maximumY = projected.first.dy;
    for (final point in projected.skip(1)) {
      if (point.dy > maximumY) maximumY = point.dy;
    }
    const tolerance = .5;
    var x = 0.0;
    var count = 0;
    for (final point in projected) {
      if ((point.dy - maximumY).abs() <= tolerance) {
        x += point.dx;
        count++;
      }
    }
    return Offset(count == 0 ? projected.first.dx : x / count, maximumY);
  }

  static bool belongsToSlice({
    required Offset objectFoot,
    required Offset pivotFoot,
    required ProjectedDepthSlice slice,
  }) {
    if (slice == ProjectedDepthSlice.all) return true;
    final isInFront = objectFoot.dy > pivotFoot.dy;
    return switch (slice) {
      ProjectedDepthSlice.all => true,
      ProjectedDepthSlice.behindPivot => !isInFront,
      ProjectedDepthSlice.inFrontOfPivot => isInFront,
    };
  }

  /// Returns the first index that belongs in front of [pivotFoot].
  ///
  /// [items] must already be sorted with [compare] using [footOf]. This turns
  /// the actor's continuous motion into a cheap binary search: a foreground
  /// canvas only needs repainting when Bit actually crosses an object's
  /// screen-space depth, not for every interpolated GNSS position.
  static int firstInFrontIndex<T>(
    List<T> items,
    Offset pivotFoot,
    Offset Function(T item) footOf,
  ) {
    var lower = 0;
    var upper = items.length;
    while (lower < upper) {
      final middle = lower + (upper - lower) ~/ 2;
      if (footOf(items[middle]).dy <= pivotFoot.dy) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower;
  }
}
