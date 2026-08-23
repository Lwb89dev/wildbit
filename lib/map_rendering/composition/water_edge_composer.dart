import 'dart:math' as math;
import 'dart:ui';

/// Semantic material selected from OSM tags and local terrain data.
enum WaterEdgeMaterial { grass, rock, sand }

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
    final clockwise = _signedArea(polygon) > 0;
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
      final normal = clockwise
          ? Offset(-tangent.dy, tangent.dx)
          : Offset(tangent.dy, -tangent.dx);
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

  double _signedArea(List<Offset> polygon) {
    var area = 0.0;
    for (var index = 0; index < polygon.length; index++) {
      final a = polygon[index];
      final b = polygon[(index + 1) % polygon.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return area / 2;
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
