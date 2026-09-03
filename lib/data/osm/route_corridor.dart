import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_bounds.dart';
import 'map_cell_grid.dart';

/// Turns a route's polyline into the set of [MapCellGrid] cells needed to
/// render/download a walkable corridor around it — a fraction of what a
/// bounding-box download over the same route would cost, since a route
/// rarely fills its own bounding box (a switchback trail, or a long one
/// like a national trail, can span a box orders of magnitude larger than
/// the ground it actually covers).
abstract final class RouteCorridor {
  /// All grid cells intersecting a [bufferMeters]-wide corridor around
  /// [points], deduplicated. [points] is resampled at roughly half the
  /// buffer width so a long straight stretch isn't computed once per GPS
  /// point while a fine switchback still gets a cell on either side.
  static List<GeoBounds> cellsCovering(
    List<LatLng> points, {
    double bufferMeters = 400,
  }) {
    if (points.isEmpty) return const [];
    const distance = Distance();
    final sampleIntervalMeters = math.max(bufferMeters / 2, 50);
    final cellKeys = <String>{};
    final cells = <GeoBounds>[];

    void addAround(LatLng point) {
      final bounds = _boundsAround(point, bufferMeters);
      for (final cell in MapCellGrid.cellsCovering(bounds)) {
        if (cellKeys.add(MapCellGrid.keyFor(cell))) cells.add(cell);
      }
    }

    addAround(points.first);
    var previous = points.first;
    for (final point in points.skip(1)) {
      final segmentMeters = distance.as(LengthUnit.Meter, previous, point);
      final steps = (segmentMeters / sampleIntervalMeters).ceil().clamp(
        1,
        2000,
      );
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        addAround(
          LatLng(
            previous.latitude + (point.latitude - previous.latitude) * t,
            previous.longitude + (point.longitude - previous.longitude) * t,
          ),
        );
      }
      previous = point;
    }
    return cells;
  }

  static GeoBounds _boundsAround(LatLng point, double radiusMeters) {
    const metersPerDegreeLatitude = 111320.0;
    final latitudeDelta = radiusMeters / metersPerDegreeLatitude;
    final longitudeDelta =
        radiusMeters /
        (metersPerDegreeLatitude *
            math.cos(point.latitude * math.pi / 180).abs().clamp(0.05, 1.0));
    return GeoBounds(
      southWest: LatLng(
        point.latitude - latitudeDelta,
        point.longitude - longitudeDelta,
      ),
      northEast: LatLng(
        point.latitude + latitudeDelta,
        point.longitude + longitudeDelta,
      ),
    );
  }
}
