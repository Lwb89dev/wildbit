import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_bounds.dart';

/// Quantizes the world into fixed-size cells so nearby viewports reuse the
/// same cached OSM fetch instead of re-downloading near-identical data.
abstract final class MapCellGrid {
  // ~2 km at mid-latitudes: small enough that a detailed hiking query stays
  // responsive in dense places, while still giving the disk cache real reuse.
  static const double cellSizeDegrees = 0.02;

  static String keyFor(GeoBounds cell) {
    return '${cell.southWest.latitude.toStringAsFixed(3)}_'
        '${cell.southWest.longitude.toStringAsFixed(3)}';
  }

  /// All grid cells that intersect [bounds], in south-to-north, west-to-east
  /// order.
  static List<GeoBounds> cellsCovering(GeoBounds bounds) {
    final startLatitudeIndex = (bounds.southWest.latitude / cellSizeDegrees)
        .floor();
    final startLongitudeIndex = (bounds.southWest.longitude / cellSizeDegrees)
        .floor();
    // North/east are exclusive for tiling purposes. Without the tiny inward
    // offset, a viewport ending exactly on a cell edge incorrectly adds a
    // whole extra row/column. The previous <= step loops added one extra even
    // away from boundaries, turning a normal GPS 2x2 request into 3x3.
    const edgeEpsilon = 1e-10;
    final endLatitudeIndex = math.max(
      startLatitudeIndex,
      ((bounds.northEast.latitude - edgeEpsilon) / cellSizeDegrees).floor(),
    );
    final endLongitudeIndex = math.max(
      startLongitudeIndex,
      ((bounds.northEast.longitude - edgeEpsilon) / cellSizeDegrees).floor(),
    );

    return [
      for (
        var latIndex = startLatitudeIndex;
        latIndex <= endLatitudeIndex;
        latIndex++
      )
        for (
          var lngIndex = startLongitudeIndex;
          lngIndex <= endLongitudeIndex;
          lngIndex++
        )
          GeoBounds(
            southWest: LatLng(
              latIndex * cellSizeDegrees,
              lngIndex * cellSizeDegrees,
            ),
            northEast: LatLng(
              (latIndex + 1) * cellSizeDegrees,
              (lngIndex + 1) * cellSizeDegrees,
            ),
          ),
    ];
  }

  /// Cells intersecting [bounds], ordered from the viewport centre outwards.
  ///
  /// A GPS-centred viewport commonly straddles two or four cache cells.  The
  /// default south-to-north order made the app download a southern neighbour
  /// before the cell containing the user. If Overpass then rate-limited the
  /// remaining requests, only terrain south of Bit became visible.
  static List<GeoBounds> cellsCoveringNearestFirst(GeoBounds bounds) {
    final cells = cellsCovering(bounds);
    final centreLatitude =
        (bounds.southWest.latitude + bounds.northEast.latitude) / 2;
    final centreLongitude =
        (bounds.southWest.longitude + bounds.northEast.longitude) / 2;
    cells.sort((first, second) {
      double squaredDistance(GeoBounds cell) {
        final latitude =
            (cell.southWest.latitude + cell.northEast.latitude) / 2;
        final longitude =
            (cell.southWest.longitude + cell.northEast.longitude) / 2;
        final latitudeDelta = latitude - centreLatitude;
        final longitudeDelta = longitude - centreLongitude;
        return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta;
      }

      final distanceOrder = squaredDistance(
        first,
      ).compareTo(squaredDistance(second));
      if (distanceOrder != 0) return distanceOrder;
      // Stable deterministic tie-breaker for viewports exactly on a boundary.
      return keyFor(first).compareTo(keyFor(second));
    });
    return cells;
  }

  /// Whether every grid cell intersecting [bounds] is represented by one of
  /// [loadedRegions]. A single successful neighbour must not make a whole
  /// GPS-centred viewport look complete.
  static bool isCoveredBy(GeoBounds bounds, Iterable<GeoBounds> loadedRegions) {
    return cellsCovering(bounds).every(
      (cell) => loadedRegions.any((region) => region.containsBounds(cell)),
    );
  }
}
