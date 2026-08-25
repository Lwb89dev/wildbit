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

  static bool insideAnyWater(LatLng point, Iterable<AreaFeature> areas) =>
      areas.where(isWaterArea).any((area) => pointInArea(point, area));

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
  }) => areas
      .where((area) => area.kind == kind)
      .any(
        (area) =>
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
            ),
      );

  static bool pointInArea(LatLng point, AreaFeature area) {
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
}
