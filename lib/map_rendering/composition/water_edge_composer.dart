import 'dart:math' as math;
import 'dart:ui';

/// Semantic material selected from OSM tags and local terrain data.
enum WaterEdgeMaterial { grass, rock, sand, mud }

/// One deterministically placed shoreline module. [normal] points away from
/// the water polygon, allowing sprites to sit on land instead of in water.
class WaterEdgePlacement {
  const WaterEdgePlacement({
    required this.position,
    required this.tangent,
    required this.normal,
    required this.material,
    required this.variant,
  });

  final Offset position;
  final Offset tangent;
  final Offset normal;
  final WaterEdgeMaterial material;
  final int variant;
}

/// Converts a closed water polygon to stable, spaced placements for shoreline
/// tile modules. It has no Flutter widget dependency and can therefore be fed
/// by any OSM geometry decoder or tested independently.
class WaterEdgeComposer {
  const WaterEdgeComposer({
    this.spacing = 16,
    this.maxPlacements,
    this.fixedPlacements,
  });

  final double spacing;
  final int? maxPlacements;

  /// Stable placement count selected from geographic geometry by production
  /// callers. It prevents shoreline modules from popping when only the screen
  /// projection/perimeter changes during zoom.
  final int? fixedPlacements;

  List<WaterEdgePlacement> compose({
    required List<Offset> polygon,
    required WaterEdgeMaterial material,
    required int chunkSeed,
  }) {
    if (polygon.length < 3 || maxPlacements == 0 || fixedPlacements == 0) {
      return const [];
    }
    final perimeter = _perimeter(polygon);
    if (perimeter == 0 || spacing <= 0) return const [];
    final desiredCount = math.max(1, (perimeter / spacing).ceil());
    final placementCount = fixedPlacements ??
        (maxPlacements == null
            ? desiredCount
            : math.min(desiredCount, maxPlacements!));
    final placements = <WaterEdgePlacement>[];

    // Sample the complete perimeter instead of restarting on each edge. This
    // prevents clusters and overlapping modules around highly detailed OSM
    // vertices while preserving every bend of the shoreline.
    for (var sample = 0; sample < placementCount; sample++) {
      final distance = (sample + .5) * perimeter / placementCount;
      final location = _locationAtDistance(polygon, distance);
      if (location == null) continue;
      final tangent = location.tangent;
      final leftNormal = Offset(-tangent.dy, tangent.dx);
      final sampleDistance = math.min(2.0, math.max(.75, spacing * .12));
      // Ring winding is not reliable for OSM multipolygons. Pick the normal
      // whose sample point is outside the water instead of alternating the
      // mud/sand side whenever the source way reverses direction.
      final normal = _contains(
            polygon,
            location.position + leftNormal * sampleDistance,
          )
          ? -leftNormal
          : leftNormal;
      placements.add(
        WaterEdgePlacement(
          position: location.position + normal * 3,
          tangent: tangent,
          normal: normal,
          material: material,
          variant: _variant(chunkSeed, location.edgeIndex, sample),
        ),
      );
    }
    return placements;
  }

  _PerimeterLocation? _locationAtDistance(
    List<Offset> polygon,
    double target,
  ) {
    var travelled = 0.0;
    for (var index = 0; index < polygon.length; index++) {
      final start = polygon[index];
      final end = polygon[(index + 1) % polygon.length];
      final delta = end - start;
      final length = delta.distance;
      if (length == 0) continue;
      if (travelled + length >= target) {
        final fraction = ((target - travelled) / length).clamp(0.0, 1.0);
        return _PerimeterLocation(
          position: Offset.lerp(start, end, fraction)!,
          tangent: delta / length,
          edgeIndex: index,
        );
      }
      travelled += length;
    }
    return null;
  }

  double _perimeter(List<Offset> polygon) {
    var total = 0.0;
    for (var index = 0; index < polygon.length; index++) {
      total +=
          (polygon[(index + 1) % polygon.length] - polygon[index]).distance;
    }
    return total;
  }

  bool _contains(List<Offset> polygon, Offset point) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final a = polygon[index];
      final b = polygon[previous];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crosses) continue;
      final x =
          (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < x) inside = !inside;
    }
    return inside;
  }

  int _variant(int seed, int edge, int sample) =>
      (seed * 31 + edge * 17 + sample * 13).abs() % 3;
}

class _PerimeterLocation {
  const _PerimeterLocation({
    required this.position,
    required this.tangent,
    required this.edgeIndex,
  });

  final Offset position;
  final Offset tangent;
  final int edgeIndex;
}
