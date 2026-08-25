import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';

/// Hard work budgets for the interactive map.
///
/// Pixel detail is progressive enhancement: exceeding these limits must lower
/// detail, never make a phone miss frames or overheat.
abstract final class MapRenderingBudget {
  static bool _mapInteracting = false;
  static bool _mapVisible = true;

  /// True while the camera is being panned, pinched or rotated. Decorative
  /// geometry temporarily uses a smaller deterministic budget in this state.
  static bool get mapInteracting => _mapInteracting;

  static void setMapInteracting(bool value) => _mapInteracting = value;

  /// IndexedStack keeps the map state mounted while another tab is visible.
  /// Timer-driven Canvas layers use this flag to avoid repainting an unseen
  /// map; TickerMode handles Flutter AnimationControllers separately.
  static bool get mapVisible => _mapVisible;

  static void setMapVisible(bool value) => _mapVisible = value;

  static final Expando<_GeographicExtent> _areaExtents =
      Expando<_GeographicExtent>('wildbit-area-extent');
  static final Expando<_GeographicExtent> _lineExtents =
      Expando<_GeographicExtent>('wildbit-line-extent');

  static const maxShoreSpritesPerPolygon = 18;
  // Routes are not capped by count: hiding a mapped way at a lower zoom can
  // lead to a wrong trail choice. Their geometry is simplified progressively
  // by OsmPixelRouteLayer instead.
  static const minLinePointDistancePixels = 2.5;

  /// Paint-time geometry LOD for linear features. The route is never removed;
  /// only redundant intermediate vertices are collapsed. Numbered or
  /// relation-backed hiking routes retain more bends at overview zooms so a
  /// junction cannot visually turn into a misleading straight segment.
  static double routePointDistancePixels(LineFeature line, double zoom) {
    final base = (18 - zoom).clamp(minLinePointDistancePixels, 14.0).toDouble();
    final isImportantTrail =
        line.kind == MapFeatureKind.trail &&
        (line.metadata.ref != null || line.metadata.hikingRoutes.isNotEmpty);
    if (!isImportantTrail) return base;
    return math.min(base, (8 - zoom * .25).clamp(3.2, 8.0).toDouble());
  }

  static int routeMaximumPoints(LineFeature line, double zoom) {
    final important =
        line.kind == MapFeatureKind.trail &&
        (line.metadata.ref != null || line.metadata.hikingRoutes.isNotEmpty);
    final normal = zoom >= 14
        ? (important ? 2048 : 1024)
        : zoom >= 10
        ? (important ? 768 : 384)
        : (important ? 320 : 180);
    if (!_mapInteracting) return normal;
    return math.min(normal, important ? 384 : 192);
  }

  /// Shared pixel-art scale curve. Decorative sprites never reach a
  /// sub-pixel size at overview zooms and never grow without a ceiling when
  /// the user zooms in.
  static double decorativeScale(
    double zoom, {
    double referenceZoom = 16,
    double min = .28,
    double max = 1.3,
  }) => math.pow(2, zoom - referenceZoom).clamp(min, max).toDouble();

  /// Smooth deterministic density LOD. The first `overview` items remain
  /// present at every zoom; closer zooms progressively reveal the rest.
  static int decorativeCount(
    double zoom, {
    required int overview,
    required int close,
    double overviewZoom = 8,
    double closeZoom = 15,
  }) {
    if (zoom <= overviewZoom) return overview;
    final t = ((zoom - overviewZoom) / (closeZoom - overviewZoom)).clamp(
      0.0,
      1.0,
    );
    final progressive = (overview + (close - overview) * t).round();
    if (!_mapInteracting) return progressive;
    return math.min(progressive, overview + ((close - overview) * .18).round());
  }

  /// Quantised decorative density used by sprite layers. Keeping the count
  /// constant inside a small zoom band prevents one tree or shrub from popping
  /// for every fractional camera tick while still exposing more detail when
  /// the user crosses a deliberate LOD boundary.
  static int decorativeLodCount(
    double zoom, {
    required int overview,
    required int close,
    int bands = 6,
    double overviewZoom = 8,
    double closeZoom = 15,
  }) {
    if (bands < 1 || close <= overview) return overview;
    if (zoom <= overviewZoom) return overview;
    final t = ((zoom - overviewZoom) / (closeZoom - overviewZoom)).clamp(
      0.0,
      1.0,
    );
    final bucket = (t * bands).round() / bands;
    final target = (overview + (close - overview) * bucket).round();
    if (!_mapInteracting) return target;
    return math.min(target, overview + ((close - overview) * .18).round());
  }

  /// Returns a deterministic prefix of a stable rank ordering. Decorative
  /// sprites therefore enter/leave the scene because of an explicit LOD
  /// budget, never because the camera happened to reorder an input list.
  ///
  /// The source is copied before sorting, so feature collections remain
  /// immutable and the method is safe to call from a paint-time projection.
  static List<T> stableDecorativeSubset<T>(
    Iterable<T> source, {
    required int count,
    required int Function(T item) rank,
  }) {
    final indexed = [
      for (final entry in source.toList(growable: false).indexed)
        (index: entry.$1, item: entry.$2, rank: rank(entry.$2)),
    ];
    if (count >= indexed.length) {
      return [for (final entry in indexed) entry.item];
    }
    indexed.sort((a, b) {
      final rankOrder = a.rank.compareTo(b.rank);
      return rankOrder != 0 ? rankOrder : a.index.compareTo(b.index);
    });
    return [for (final entry in indexed.take(math.max(0, count))) entry.item];
  }

  static double biomeDensity(MapFeatureKind kind) => switch (kind) {
    MapFeatureKind.forest => 1.0,
    MapFeatureKind.park => .68,
    MapFeatureKind.meadow => .34,
    MapFeatureKind.mountainRock => .22,
    _ => 0,
  };

  static int poiPriority(PoiType type) => switch (type) {
    PoiType.shelter ||
    PoiType.viewpoint ||
    PoiType.guidepost ||
    PoiType.summit ||
    PoiType.ford ||
    PoiType.barrier => 0,
    PoiType.waterSource || PoiType.campsite => 1,
    PoiType.parking => 2,
    PoiType.tree => 3,
  };

  static double poiMarkerSize(PoiType type, double zoom) {
    // Shelters are geographic structures, not compact pin icons. At walking
    // zoom they must read as buildings and remain larger than Bit and signs.
    if (type == PoiType.shelter) {
      final t = ((zoom - 11) / 5).clamp(0.0, 1.0);
      return 32 + (76 - 32) * t;
    }
    final base = (18 + (zoom - 11) * 3.5).clamp(16.0, 38.0).toDouble();
    final multiplier = switch (type) {
      PoiType.shelter => 1.0,
      PoiType.viewpoint => 1.05,
      PoiType.guidepost => .96,
      PoiType.campsite => .9,
      PoiType.summit => 1.05,
      PoiType.parking || PoiType.waterSource => .88,
      PoiType.tree => 1.0,
      PoiType.ford => 1.08,
      PoiType.barrier => .96,
    };
    return (base * multiplier).clamp(15.0, 48.0).toDouble();
  }

  /// Labels have their own LOD. Marker existence is deliberately independent
  /// from this threshold: an important object can lose its name when crowded,
  /// but never disappear from the map.
  static double poiLabelMinZoom(PoiType type) => switch (type) {
    PoiType.shelter || PoiType.summit => 12,
    PoiType.viewpoint => 13,
    PoiType.guidepost || PoiType.waterSource => 14,
    PoiType.campsite => 15,
    PoiType.parking => 16,
    PoiType.tree => double.infinity,
    PoiType.ford || PoiType.barrier => 14,
  };

  static bool areaMayBeVisible(AreaFeature area, LatLngBounds viewport) {
    final extent = _areaExtents[area] ??= _GeographicExtent.from(area.ring);
    return extent.overlaps(viewport);
  }

  static bool lineMayBeVisible(LineFeature line, LatLngBounds viewport) {
    final extent = _lineExtents[line] ??= _GeographicExtent.from(line.points);
    return extent.overlaps(viewport);
  }
}

class _GeographicExtent {
  const _GeographicExtent({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.isEmpty,
  });

  factory _GeographicExtent.from(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      return const _GeographicExtent(
        south: 0,
        north: 0,
        west: 0,
        east: 0,
        isEmpty: true,
      );
    }
    var south = coordinates.first.latitude;
    var north = south;
    var west = coordinates.first.longitude;
    var east = west;
    for (final coordinate in coordinates.skip(1)) {
      south = coordinate.latitude < south ? coordinate.latitude : south;
      north = coordinate.latitude > north ? coordinate.latitude : north;
      west = coordinate.longitude < west ? coordinate.longitude : west;
      east = coordinate.longitude > east ? coordinate.longitude : east;
    }
    return _GeographicExtent(
      south: south,
      north: north,
      west: west,
      east: east,
      isEmpty: false,
    );
  }

  final double south;
  final double north;
  final double west;
  final double east;
  final bool isEmpty;

  bool overlaps(LatLngBounds viewport) {
    if (isEmpty) return false;
    // The small margin avoids a detail pop at the viewport edge while keeping
    // the culling check inexpensive.
    const margin = .002;
    return north >= viewport.south - margin &&
        south <= viewport.north + margin &&
        east >= viewport.west - margin &&
        west <= viewport.east + margin;
  }
}
