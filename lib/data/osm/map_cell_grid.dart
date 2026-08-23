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

  static GeoBounds _cellContaining(LatLng point) {
    final swLat = (point.latitude / cellSizeDegrees).floor() * cellSizeDegrees;
    final swLng = (point.longitude / cellSizeDegrees).floor() * cellSizeDegrees;
    return GeoBounds(
      southWest: LatLng(swLat, swLng),
      northEast: LatLng(swLat + cellSizeDegrees, swLng + cellSizeDegrees),
    );
  }

  /// All grid cells that intersect [bounds], in south-to-north, west-to-east
  /// order.
  static List<GeoBounds> cellsCovering(GeoBounds bounds) {
    final startCell = _cellContaining(bounds.southWest);
    final latSteps =
        ((bounds.northEast.latitude - startCell.southWest.latitude) /
                cellSizeDegrees)
            .ceil();
    final lngSteps =
        ((bounds.northEast.longitude - startCell.southWest.longitude) /
                cellSizeDegrees)
            .ceil();

    return [
      for (var latIndex = 0; latIndex <= math.max(latSteps, 0); latIndex++)
        for (var lngIndex = 0; lngIndex <= math.max(lngSteps, 0); lngIndex++)
          GeoBounds(
            southWest: LatLng(
              startCell.southWest.latitude + latIndex * cellSizeDegrees,
              startCell.southWest.longitude + lngIndex * cellSizeDegrees,
            ),
            northEast: LatLng(
              startCell.southWest.latitude + (latIndex + 1) * cellSizeDegrees,
              startCell.southWest.longitude + (lngIndex + 1) * cellSizeDegrees,
            ),
          ),
    ];
  }
}
