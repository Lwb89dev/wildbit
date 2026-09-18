import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_bounds.dart';

/// Quantizes the world into fixed-size cells so nearby viewports reuse the
/// same cached OSM fetch instead of re-downloading near-identical data.
abstract final class MapCellGrid {
  // ~2 km at mid-latitudes: small enough that a detailed hiking query stays
  // responsive in dense places, while still giving the disk cache real reuse.
  static const double cellSizeDegrees = 0.02;
  static const int _longitudeCellCount = 18000;
  static const int _minimumLongitudeIndex = -9000;
  static const int _maximumLongitudeIndex = 8999;
  static const int _fullSortCellLimit = 4096;

  static String keyFor(GeoBounds cell) {
    return '${cell.southWest.latitude.toStringAsFixed(3)}_'
        '${cell.southWest.longitude.toStringAsFixed(3)}';
  }

  /// All grid cells that intersect [bounds], in south-to-north, west-to-east
  /// order.
  static List<GeoBounds> cellsCovering(GeoBounds bounds) {
    // North/east are exclusive for tiling purposes. Without the tiny inward
    // offset, a viewport ending exactly on a cell edge incorrectly adds a
    // whole extra row/column. The previous <= step loops added one extra even
    // away from boundaries, turning a normal GPS 2x2 request into 3x3.
    const edgeEpsilon = 1e-10;
    final south = bounds.southWest.latitude.clamp(-90.0, 90.0 - edgeEpsilon);
    final north = bounds.northEast.latitude.clamp(-90.0, 90.0);
    if (north < south) return const [];
    final startLatitudeIndex = (south / cellSizeDegrees).floor();
    final endLatitudeIndex = math.max(
      startLatitudeIndex,
      ((north - edgeEpsilon) / cellSizeDegrees).floor(),
    );

    final cells = <GeoBounds>[];
    final seen = <String>{};
    for (final (west, east) in _longitudeIntervals(bounds)) {
      final startLongitudeIndex = (west / cellSizeDegrees).floor();
      final endLongitudeIndex = math.max(
        startLongitudeIndex,
        ((east - edgeEpsilon) / cellSizeDegrees).floor(),
      );
      for (
        var latIndex = startLatitudeIndex;
        latIndex <= endLatitudeIndex;
        latIndex++
      ) {
        for (
          var lngIndex = startLongitudeIndex;
          lngIndex <= endLongitudeIndex;
          lngIndex++
        ) {
          final cell = GeoBounds(
            southWest: LatLng(
              latIndex * cellSizeDegrees,
              lngIndex * cellSizeDegrees,
            ),
            northEast: LatLng(
              (latIndex + 1) * cellSizeDegrees,
              (lngIndex + 1) * cellSizeDegrees,
            ),
          );
          if (seen.add(keyFor(cell))) cells.add(cell);
        }
      }
    }
    return cells;
  }

  static List<(double, double)> _longitudeIntervals(GeoBounds bounds) {
    const fullCircle = 360.0;
    final rawSpan = bounds.northEast.longitude - bounds.southWest.longitude;
    if (rawSpan.abs() >= fullCircle) return const [(-180, 180)];
    var span = rawSpan;
    while (span < 0) {
      span += fullCircle;
    }
    final west = _normalizeLongitude(bounds.southWest.longitude);
    final unwrappedEast = west + span;
    if (unwrappedEast <= 180) return [(west, unwrappedEast)];
    return [(west, 180), (-180, unwrappedEast - fullCircle)];
  }

  static double _normalizeLongitude(double longitude) {
    if (longitude >= -180 && longitude < 180) return longitude;
    final normalized = (longitude + 180) % 360;
    return (normalized < 0 ? normalized + 360 : normalized) - 180;
  }

  /// Cells intersecting [bounds], ordered from the viewport centre outwards.
  ///
  /// A GPS-centred viewport commonly straddles two or four cache cells.  The
  /// default south-to-north order made the app download a southern neighbour
  /// before the cell containing the user. If Overpass then rate-limited the
  /// remaining requests, only terrain south of Bit became visible.
  static List<GeoBounds> cellsCoveringNearestFirst(GeoBounds bounds) {
    return cellsCoveringPrioritized(
      bounds,
      priority: LatLng(
        (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
        _midpointLongitude(
          bounds.southWest.longitude,
          bounds.northEast.longitude,
        ),
      ),
    );
  }

  static double _midpointLongitude(double west, double east) {
    var delta = east - west;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return _normalizeLongitude(west + delta / 2);
  }

  /// Returns only the nearest [limit] cells without materialising an entire
  /// overview viewport, which can contain millions of 0.02° cells.
  static List<GeoBounds> cellsCoveringPrioritizedLimited(
    GeoBounds bounds, {
    required LatLng priority,
    required int limit,
  }) {
    if (limit <= 0) return const [];
    if (cellCount(bounds) <= _fullSortCellLimit) {
      return cellsCoveringPrioritized(
        bounds,
        priority: priority,
      ).take(limit).toList(growable: false);
    }

    final (minimumLatitudeIndex, maximumLatitudeIndex) = _latitudeIndexRange(
      bounds,
    );
    if (maximumLatitudeIndex < minimumLatitudeIndex) return const [];
    final longitudeRanges = _longitudeIndexRanges(bounds);
    final priorityLatitudeIndex = (priority.latitude / cellSizeDegrees)
        .floor()
        .clamp(minimumLatitudeIndex, maximumLatitudeIndex);
    final priorityLongitudeIndex =
        (_normalizeLongitude(priority.longitude) / cellSizeDegrees).floor();
    final anchorLongitudeIndex = _nearestLongitudeIndex(
      priorityLongitudeIndex,
      longitudeRanges,
    );

    final candidates = <String, GeoBounds>{};
    var radius = 0;
    while (candidates.length < limit && radius <= _longitudeCellCount) {
      for (
        var latitudeOffset = -radius;
        latitudeOffset <= radius;
        latitudeOffset++
      ) {
        for (
          var longitudeOffset = -radius;
          longitudeOffset <= radius;
          longitudeOffset++
        ) {
          if (radius > 0 &&
              latitudeOffset.abs() != radius &&
              longitudeOffset.abs() != radius) {
            continue;
          }
          final latitudeIndex = priorityLatitudeIndex + latitudeOffset;
          if (latitudeIndex < minimumLatitudeIndex ||
              latitudeIndex > maximumLatitudeIndex) {
            continue;
          }
          final longitudeIndex = _wrapLongitudeIndex(
            anchorLongitudeIndex + longitudeOffset,
          );
          if (!_indexInRanges(longitudeIndex, longitudeRanges)) continue;
          final cell = _cellForIndices(latitudeIndex, longitudeIndex);
          candidates[keyFor(cell)] = cell;
        }
      }
      radius++;
    }
    final ordered = candidates.values.toList(growable: false)
      ..sort((first, second) => _compareByPriority(first, second, priority));
    return ordered.take(limit).toList(growable: false);
  }

  static int cellCount(GeoBounds bounds) {
    final (minimumLatitudeIndex, maximumLatitudeIndex) = _latitudeIndexRange(
      bounds,
    );
    if (maximumLatitudeIndex < minimumLatitudeIndex) return 0;
    final latitudeCount = maximumLatitudeIndex - minimumLatitudeIndex + 1;
    final longitudeCount = _longitudeIndexRanges(
      bounds,
    ).fold<int>(0, (count, range) => count + range.$2 - range.$1 + 1);
    return latitudeCount * longitudeCount;
  }

  /// Orders intersecting cells around an explicit geographic priority.
  ///
  /// The viewport centre is not always the hiker: during heading-follow and
  /// after a delayed camera move Bit can be close to an edge. Passing the GNSS
  /// point guarantees its cell is requested before neighbouring terrain.
  static List<GeoBounds> cellsCoveringPrioritized(
    GeoBounds bounds, {
    required LatLng priority,
  }) {
    final cells = cellsCovering(bounds);
    cells.sort((first, second) => _compareByPriority(first, second, priority));
    return cells;
  }

  static int _compareByPriority(
    GeoBounds first,
    GeoBounds second,
    LatLng priority,
  ) {
    double squaredDistance(GeoBounds cell) {
      final latitude = (cell.southWest.latitude + cell.northEast.latitude) / 2;
      final longitude =
          (cell.southWest.longitude + cell.northEast.longitude) / 2;
      final latitudeDelta = latitude - priority.latitude;
      final rawLongitudeDelta =
          (_normalizeLongitude(longitude) -
                  _normalizeLongitude(priority.longitude))
              .abs();
      final longitudeDelta = math.min(
        rawLongitudeDelta,
        360 - rawLongitudeDelta,
      );
      return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta;
    }

    final distanceOrder = squaredDistance(
      first,
    ).compareTo(squaredDistance(second));
    if (distanceOrder != 0) return distanceOrder;
    return keyFor(first).compareTo(keyFor(second));
  }

  static (int, int) _latitudeIndexRange(GeoBounds bounds) {
    const edgeEpsilon = 1e-10;
    final south = bounds.southWest.latitude.clamp(-90.0, 90.0 - edgeEpsilon);
    final north = bounds.northEast.latitude.clamp(-90.0, 90.0);
    if (north < south) return (1, 0);
    final start = (south / cellSizeDegrees).floor();
    return (
      start,
      math.max(start, ((north - edgeEpsilon) / cellSizeDegrees).floor()),
    );
  }

  static List<(int, int)> _longitudeIndexRanges(GeoBounds bounds) {
    const edgeEpsilon = 1e-10;
    return [
      for (final (west, east) in _longitudeIntervals(bounds))
        (
          (west / cellSizeDegrees).floor(),
          math.max(
            (west / cellSizeDegrees).floor(),
            ((east - edgeEpsilon) / cellSizeDegrees).floor(),
          ),
        ),
    ];
  }

  static int _nearestLongitudeIndex(
    int priorityIndex,
    List<(int, int)> ranges,
  ) {
    var best = ranges.first.$1;
    var bestDistance = _longitudeIndexDistance(priorityIndex, best);
    for (final (start, end) in ranges) {
      for (final shifted in [
        priorityIndex - _longitudeCellCount,
        priorityIndex,
        priorityIndex + _longitudeCellCount,
      ]) {
        final candidate = shifted.clamp(start, end);
        final distance = _longitudeIndexDistance(priorityIndex, candidate);
        if (distance < bestDistance) {
          best = candidate;
          bestDistance = distance;
        }
      }
    }
    return _wrapLongitudeIndex(best);
  }

  static int _longitudeIndexDistance(int first, int second) {
    final distance = (first - second).abs() % _longitudeCellCount;
    return math.min(distance, _longitudeCellCount - distance);
  }

  static int _wrapLongitudeIndex(int index) {
    var wrapped = index;
    while (wrapped < _minimumLongitudeIndex) {
      wrapped += _longitudeCellCount;
    }
    while (wrapped > _maximumLongitudeIndex) {
      wrapped -= _longitudeCellCount;
    }
    return wrapped;
  }

  static bool _indexInRanges(int index, List<(int, int)> ranges) =>
      ranges.any((range) => index >= range.$1 && index <= range.$2);

  static GeoBounds _cellForIndices(int latitudeIndex, int longitudeIndex) =>
      GeoBounds(
        southWest: LatLng(
          latitudeIndex * cellSizeDegrees,
          longitudeIndex * cellSizeDegrees,
        ),
        northEast: LatLng(
          (latitudeIndex + 1) * cellSizeDegrees,
          (longitudeIndex + 1) * cellSizeDegrees,
        ),
      );

  /// Whether every grid cell intersecting [bounds] is represented by one of
  /// [loadedRegions]. A single successful neighbour must not make a whole
  /// GPS-centred viewport look complete.
  static bool isCoveredBy(GeoBounds bounds, Iterable<GeoBounds> loadedRegions) {
    final loaded = loadedRegions.toList(growable: false);
    if (loaded.any((region) => region.containsBounds(bounds))) return true;
    if (cellCount(bounds) > _fullSortCellLimit) return false;
    return cellsCovering(
      bounds,
    ).every((cell) => loaded.any((region) => region.containsBounds(cell)));
  }
}
