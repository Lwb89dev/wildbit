import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../performance/map_rendering_budget.dart';
import 'geographic_ring_topology.dart';

/// Small, deterministic geometry rules used by the pixel compositor. They
/// operate on geographic coordinates before projection, so artwork cannot
/// accidentally leak across a lake or a coastline because of screen scaling.
abstract final class MapGeometryRules {
  static bool isWaterArea(AreaFeature area) =>
      area.kind == MapFeatureKind.water;

  /// Conservatively narrows collision checks to features whose cached bounds
  /// overlap the polygon being decorated. Procedural forest sampling used to
  /// scan every water/building/way in the loaded map for every attempted
  /// tree, which became an UI-isolate stall in feature-dense mountain cells.
  static List<AreaFeature> areasNearArea(
    AreaFeature reference,
    Iterable<AreaFeature> areas, {
    double marginDegrees = .0004,
  }) {
    final extent = _extentForArea(reference);
    return areas
        .where(
          (area) =>
              identical(area, reference) ||
              extent.overlaps(_extentForArea(area), marginDegrees),
        )
        .toList(growable: false);
  }

  static List<LineFeature> linesNearArea(
    AreaFeature reference,
    Iterable<LineFeature> lines, {
    double marginDegrees = .0004,
  }) {
    final extent = _extentForArea(reference);
    return lines
        .where((line) => extent.overlaps(_extentForLine(line), marginDegrees))
        .toList(growable: false);
  }

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
    return GeographicRingTopology.contains(polygon, point);
  }

  static double polygonArea(List<LatLng> polygon) =>
      GeographicRingTopology.area(polygon);

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

  /// Conservative point-anchor collision used by procedural decoration.
  /// Priority POIs are semantic evidence and must keep a clear visual ground
  /// around them; a generated tree or shrub may not grow through a refuge,
  /// guidepost, spring or other mapped marker.
  static bool nearAnyPoint(
    LatLng point,
    Iterable<LatLng> anchors, {
    double thresholdDegrees = .00018,
  }) {
    final thresholdSquared = thresholdDegrees * thresholdDegrees;
    for (final anchor in anchors) {
      final longitude = point.longitude - anchor.longitude;
      final latitude = point.latitude - anchor.latitude;
      if (longitude * longitude + latitude * latitude <= thresholdSquared) {
        return true;
      }
    }
    return false;
  }

  static double _distanceSquaredToSegment(LatLng p, LatLng a, LatLng b) {
    final endLongitude = _longitudeNear(b.longitude, a.longitude);
    final pointLongitude = _longitudeNear(p.longitude, a.longitude);
    final dx = endLongitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) {
      final px = pointLongitude - a.longitude;
      final py = p.latitude - a.latitude;
      return px * px + py * py;
    }
    final t =
        ((((p.longitude - a.longitude) * dx) +
                    ((p.latitude - a.latitude) * dy)) /
                (dx * dx + dy * dy))
            .clamp(0.0, 1.0)
            .toDouble();
    final px = pointLongitude - (a.longitude + t * dx);
    final py = p.latitude - (a.latitude + t * dy);
    return px * px + py * py;
  }

  static double _longitudeNear(double longitude, double reference) {
    var result = longitude;
    while (result - reference > 180) {
      result -= 360;
    }
    while (result - reference < -180) {
      result += 360;
    }
    return result;
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

/// Small spatial index for point-like scene anchors.
///
/// It keeps collision checks for generated decoration local even when an OSM
/// response contains hundreds of POIs. Longitude cells wrap at the dateline,
/// matching the geographic comparison used by [containsNear].
class MapPointAnchorIndex {
  MapPointAnchorIndex(Iterable<LatLng> anchors, {this.cellSizeDegrees = .0005})
    : assert(cellSizeDegrees > 0) {
    for (final anchor in anchors) {
      (_cells[_cellFor(anchor)] ??= []).add(anchor);
    }
  }

  final double cellSizeDegrees;
  final Map<({int latitude, int longitude}), List<LatLng>> _cells = {};

  bool containsNear(LatLng point, {double thresholdDegrees = .00018}) {
    if (_cells.isEmpty) return false;
    final range = (thresholdDegrees / cellSizeDegrees).ceil();
    final base = _cellFor(point);
    final thresholdSquared = thresholdDegrees * thresholdDegrees;
    for (
      var latitude = base.latitude - range;
      latitude <= base.latitude + range;
      latitude++
    ) {
      for (
        var longitude = base.longitude - range;
        longitude <= base.longitude + range;
        longitude++
      ) {
        for (final anchor
            in _cells[(
                  latitude: latitude,
                  longitude: _wrapLongitudeCell(longitude),
                )] ??
                const <LatLng>[]) {
          var longitudeDelta = point.longitude - anchor.longitude;
          if (longitudeDelta > 180) longitudeDelta -= 360;
          if (longitudeDelta < -180) longitudeDelta += 360;
          final latitudeDelta = point.latitude - anchor.latitude;
          if (longitudeDelta * longitudeDelta + latitudeDelta * latitudeDelta <=
              thresholdSquared) {
            return true;
          }
        }
      }
    }
    return false;
  }

  ({int latitude, int longitude}) _cellFor(LatLng point) => (
    latitude: (point.latitude / cellSizeDegrees).floor(),
    longitude: _wrapLongitudeCell(
      ((_normalizeLongitude(point.longitude) + 180) / cellSizeDegrees).floor(),
    ),
  );

  int _wrapLongitudeCell(int value) {
    final count = (360 / cellSizeDegrees).ceil();
    final wrapped = value % count;
    return wrapped < 0 ? wrapped + count : wrapped;
  }

  double _normalizeLongitude(double value) {
    var normalized = value;
    while (normalized < -180) {
      normalized += 360;
    }
    while (normalized >= 180) {
      normalized -= 360;
    }
    return normalized;
  }
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
    if (east - west > 180) {
      final wrappedWest = east;
      east = west;
      west = wrappedWest;
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
      (west <= east
          ? point.longitude >= west && point.longitude <= east
          : point.longitude >= west || point.longitude <= east);

  bool isNear(LatLng point, double margin) =>
      !isEmpty &&
      point.latitude >= south - margin &&
      point.latitude <= north + margin &&
      MapRenderingBudget.longitudeIntervalsOverlap(
        west,
        east,
        point.longitude,
        point.longitude,
        margin: margin,
      );

  bool overlaps(_Extent other, double margin) =>
      !isEmpty &&
      !other.isEmpty &&
      north + margin >= other.south &&
      south - margin <= other.north &&
      MapRenderingBudget.longitudeIntervalsOverlap(
        west,
        east,
        other.west,
        other.east,
        margin: margin,
      );
}
