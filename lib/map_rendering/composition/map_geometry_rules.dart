import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';

/// Small, deterministic geometry rules used by the pixel compositor. They
/// operate on geographic coordinates before projection, so artwork cannot
/// accidentally leak across a lake or a coastline because of screen scaling.
abstract final class MapGeometryRules {
  static bool isWaterArea(AreaFeature area) =>
      area.kind == MapFeatureKind.water;

  static bool insideAnyWater(LatLng point, Iterable<AreaFeature> areas) {
    for (final area in areas) {
      if (isWaterArea(area) && pointInArea(point, area)) return true;
    }
    return false;
  }

  static bool insideAnyAreaKind(
    LatLng point,
    Iterable<AreaFeature> areas,
    MapFeatureKind kind,
  ) => areas
      .where((area) => area.kind == kind)
      .any((area) => pointInArea(point, area));

  static bool nearAnyAreaBoundary(
    LatLng point,
    Iterable<AreaFeature> areas,
    MapFeatureKind kind, {
    double thresholdDegrees = .00008,
  }) {
    for (final area in areas) {
      if (area.kind != kind ||
          !_extentForArea(area).isNear(point, thresholdDegrees)) {
        continue;
      }
      if (nearPolygonBoundary(
            point,
            area.ring,
            thresholdDegrees: thresholdDegrees,
          ) ||
          area.holes.any(
            (hole) => nearPolygonBoundary(
              point,
              hole,
              thresholdDegrees: thresholdDegrees,
            ),
          )) {
        return true;
      }
    }
    return false;
  }

  /// Single-pass building collision used by procedural vegetation. The old
  /// implementation traversed every city footprint twice per candidate
  /// (inside, then boundary), multiplying thousands of buildings by hundreds
  /// of generated sprites on the UI isolate.
  static bool insideOrNearAnyAreaKind(
    LatLng point,
    Iterable<AreaFeature> areas,
    MapFeatureKind kind, {
    double thresholdDegrees = .00008,
  }) {
    for (final area in areas) {
      if (area.kind != kind ||
          !_extentForArea(area).isNear(point, thresholdDegrees)) {
        continue;
      }
      if (pointInArea(point, area) ||
          nearPolygonBoundary(
            point,
            area.ring,
            thresholdDegrees: thresholdDegrees,
          ) ||
          area.holes.any(
            (hole) => nearPolygonBoundary(
              point,
              hole,
              thresholdDegrees: thresholdDegrees,
            ),
          )) {
        return true;
      }
    }
    return false;
  }

  static bool pointInArea(LatLng point, AreaFeature area) {
    if (!_extentForArea(area).contains(point)) return false;
    if (!pointInPolygon(point, area.ring)) return false;
    return !area.holes.any((hole) => pointInPolygon(point, hole));
  }

  static bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          (a.latitude > point.latitude) != (b.latitude > point.latitude);
      if (!crosses) continue;
      final longitude =
          (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (point.longitude < longitude) inside = !inside;
    }
    return inside;
  }

  static double polygonArea(List<LatLng> polygon) {
    if (polygon.length < 3) return 0;
    var area = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      area += a.longitude * b.latitude - b.longitude * a.latitude;
    }
    return area.abs() / 2;
  }

  static bool nearPolygonBoundary(
    LatLng point,
    List<LatLng> polygon, {
    double thresholdDegrees = .00035,
  }) {
    if (polygon.length < 2) return false;
    final thresholdSquared = thresholdDegrees * thresholdDegrees;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (_distanceSquaredToSegment(point, a, b) <= thresholdSquared) {
        return true;
      }
    }
    return false;
  }

  static bool nearAnyLine(
    LatLng point,
    Iterable<LineFeature> lines, {
    double thresholdDegrees = .00028,
  }) {
    final thresholdSquared = thresholdDegrees * thresholdDegrees;
    for (final line in lines) {
      if (!_extentForLine(line).isNear(point, thresholdDegrees)) continue;
      for (var i = 0; i + 1 < line.points.length; i++) {
        if (_distanceSquaredToSegment(
              point,
              line.points[i],
              line.points[i + 1],
            ) <=
            thresholdSquared) {
          return true;
        }
      }
    }
    return false;
  }

  static double _distanceSquaredToSegment(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) {
      final px = p.longitude - a.longitude;
      final py = p.latitude - a.latitude;
      return px * px + py * py;
    }
    final t =
        ((((p.longitude - a.longitude) * dx) +
                    ((p.latitude - a.latitude) * dy)) /
                (dx * dx + dy * dy))
            .clamp(0.0, 1.0)
            .toDouble();
    final px = p.longitude - (a.longitude + t * dx);
    final py = p.latitude - (a.latitude + t * dy);
    return px * px + py * py;
  }

  static final Expando<_Extent> _areaExtents = Expando<_Extent>(
    'wildbit-geometry-area-extent',
  );
  static final Expando<_Extent> _lineExtents = Expando<_Extent>(
    'wildbit-geometry-line-extent',
  );

  static _Extent _extentForArea(AreaFeature area) =>
      _areaExtents[area] ??= _Extent.from(area.ring);

  static _Extent _extentForLine(LineFeature line) =>
      _lineExtents[line] ??= _Extent.from(line.points);
}

class _Extent {
  const _Extent(this.south, this.north, this.west, this.east, this.isEmpty);

  factory _Extent.from(List<LatLng> points) {
    if (points.isEmpty) return const _Extent(0, 0, 0, 0, true);
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final point in points.skip(1)) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    return _Extent(south, north, west, east, false);
  }

  final double south;
  final double north;
  final double west;
  final double east;
  final bool isEmpty;

  bool contains(LatLng point) =>
      !isEmpty &&
      point.latitude >= south &&
      point.latitude <= north &&
      point.longitude >= west &&
      point.longitude <= east;

  bool isNear(LatLng point, double margin) =>
      !isEmpty &&
      point.latitude >= south - margin &&
      point.latitude <= north + margin &&
      point.longitude >= west - margin &&
      point.longitude <= east + margin;
}
