import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';

/// Hard work budgets for the interactive map.
///
/// Pixel detail is progressive enhancement: exceeding these limits must lower
/// detail, never make a phone miss frames or overheat.
abstract final class MapRenderingBudget {
  static bool _mapInteracting = false;
  static bool _mapVisible = true;
  static double _deviceFactor = 1;
  static double _sceneFactor = 1;
  static double _frameFactor = 1;
  static int _frameAmbientTickDivisor = 1;
  static bool _ambientIdle = false;
  static bool _actorWalking = false;
  static bool _actorInterpolating = false;
  // Frame timings are a rolling signal and naturally fluctuate around the
  // 16.7 ms budget. Keep a small amount of hysteresis so a borderline scene
  // does not rebuild the entire map on every sample while it toggles between
  // two decorative tiers.
  static int _framePressureLevel = 0;

  /// Quantised pressure tier used by the local profile panel and tests.
  /// 0 is full detail, 1/2 reduce optional decoration progressively and 3 is
  /// the most conservative tier. Mapped geometry is unaffected by this tier.
  static int get framePressureLevel => _framePressureLevel;

  /// Configures decorative quality from the physical viewport, not from a
  /// device-name allowlist. This remains useful on new Android hardware and
  /// behaves deterministically in widget tests where no view is available.
  static void configureDevice({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    final pixels =
        logicalWidth * logicalHeight * devicePixelRatio * devicePixelRatio;
    // Rendering cost grows with physical pixels. The previous ordering was
    // backwards: a dense tablet could begin at full decoration while a
    // smaller phone started reduced. Start conservatively on every field
    // handset, and progressively lower only optional sprites as the surface
    // becomes more expensive. The frame-pressure budget can still reduce
    // further on a slower CPU/GPU.
    _deviceFactor = pixels >= 4.5e6
        ? .60
        : pixels >= 3.2e6
        ? .68
        : pixels >= 1.7e6
        ? .78
        : .86;
  }

  @visibleForTesting
  static void resetDeviceProfile() {
    _deviceFactor = 1;
    _sceneFactor = 1;
  }

  /// Scene complexity is intentionally a soft budget. It can reduce
  /// procedural decoration in a dense OSM cell, but never affects mapped
  /// lines, water polygons or safety-relevant POIs.
  static void configureScene(MapFeatureCollection features) {
    var vertices = 0;
    for (final area in features.areas) {
      vertices += area.ring.length;
      for (final hole in area.holes) {
        vertices += hole.length;
      }
    }
    for (final line in features.lines) {
      vertices += line.points.length;
    }
    // Counting only features underestimates a pathological multipolygon or a
    // very densely surveyed way by orders of magnitude. This executes only
    // when the retained viewport collection changes, never in a paint loop.
    final complexity =
        features.areas.length +
        features.lines.length +
        features.pois.length * 2 +
        vertices ~/ 10;
    _sceneFactor = complexity >= 2600
        ? .68
        : complexity >= 1200
        ? .84
        : 1.0;
  }

  static double get decorativeQuality =>
      math.min(math.min(_deviceFactor, _sceneFactor), _frameFactor);

  /// Adapts only decorative density to measured frame pressure. Mapped
  /// geometry (trails, water and safety-relevant POIs) is never hidden.
  /// Values are intentionally quantised to avoid oscillating LOD on every
  /// timing callback.
  static bool configureFramePressure({
    required int averageBuildMicros,
    required int averageRasterMicros,
    int p95FrameMicros = 0,
    int targetFrameMicros = 16667,
  }) {
    // An average can look healthy while regular expensive frames still make
    // pan feel sticky. Feed the p95 into the same hysteretic budget so the
    // quality tier responds to the user-visible tail, not just its mean.
    final average = math.max(
      p95FrameMicros,
      math.max(averageBuildMicros, averageRasterMicros),
    );
    final target = math.max(1, targetFrameMicros);
    final previousLevel = _framePressureLevel;
    final nextLevel = _nextFramePressureLevel(
      average: average,
      target: target,
      current: previousLevel,
    );
    if (nextLevel == previousLevel) return false;
    _framePressureLevel = nextLevel;
    _frameFactor = _frameFactorForLevel(nextLevel);
    // Under sustained pressure ambient animation wakes the device less often.
    // Geography remains visible; only water/flower motion slows down.
    _frameAmbientTickDivisor = nextLevel <= 1
        ? 1
        : nextLevel == 2
        ? 2
        : 3;
    _applyAmbientTickDivisor();
    return true;
  }

  static int _nextFramePressureLevel({
    required int average,
    required int target,
    required int current,
  }) {
    // A very healthy sample is strong evidence that pressure has gone away;
    // recover directly to full detail. This also prevents a device that has
    // just finished a one-off shader compilation from staying degraded.
    if (average <= target * .60) return 0;

    // Enter a tier immediately when the current tier is too optimistic. The
    // recovery thresholds below are deliberately lower than these thresholds
    // (hysteresis), avoiding rapid up/down rebuilds around a boundary.
    if (average > target * 1.4) return math.max(current, 3);
    // Tier one is deliberately gentle; it is not enough for a dense forest
    // that is already missing its frame budget by roughly ten percent. Move
    // such a scene straight to the meaningful 34% decoration reduction of
    // tier two, before the raster queue grows into the 20+ ms range.
    if (average > target * 1.10) return math.max(current, 2);
    if (average > target) return math.max(current, 1);

    return switch (current) {
      3 => average <= target * .80 ? 2 : 3,
      2 => average <= target * .72 ? 1 : 2,
      1 => average <= target * .65 ? 0 : 1,
      _ => 0,
    };
  }

  static double _frameFactorForLevel(int level) => switch (level) {
    0 => 1.0,
    1 => .84,
    2 => .66,
    // Tier 3 is entered only after sustained p95 pressure (> 1.4× target).
    // At that point a dense imported forest can still contain hundreds of
    // stable trees, but retaining 35% left a real OSM pan just over the
    // 16.7 ms budget. 30% keeps a recognisable, non-grid-like canopy while
    // shedding the final optional sprites needed to keep the map responsive.
    // Routes, water, Bit and priority POIs do not read this multiplier.
    _ => .30,
  };

  /// Restores the adaptive quality tier before a deterministic profile pass.
  /// This is also useful to tests that must not inherit another scenario's
  /// sustained pressure state.
  static void resetFramePressure() {
    _framePressureLevel = 0;
    _frameFactor = 1;
    _frameAmbientTickDivisor = 1;
    _ambientIdle = false;
    _applyAmbientTickDivisor();
  }

  /// Continuous banks remain visible at every quality. This affects only
  /// optional edge modules drawn over the geometric shoreline.
  static int shoreDetailCount(int requested) =>
      math.max(4, (requested * decorativeQuality).round());

  /// A solid, correctly placed water body remains mandatory; animated
  /// texture, highlights and bank tiles are dispensable under pressure.
  static bool get ambientDetailEnabled => decorativeQuality >= .74;

  /// True while the camera is being panned, pinched or rotated. Expensive
  /// secondary details may be deferred in this state, but already visible
  /// geographic sprites keep the same identity and population.
  static bool get mapInteracting => _mapInteracting;

  static void setMapInteracting(bool value) {
    if (_mapInteracting == value) return;
    _mapInteracting = value;
    // A new gesture is an explicit signal that the hiker is looking at the
    // map again. Restore the normal, deliberately low-rate water cadence;
    // the pressure budget may still make it slower on a weaker device.
    if (value) setAmbientIdle(false);
    // Camera motion already produces continuous visual movement. Stop the
    // periodic water/flower wake-up entirely until the gesture settles.
    ambientClock.setSuspended(value);
    // Keep a measured pressure tier after the gesture settles. Resetting it
    // here made a map that was demonstrably too expensive while panning jump
    // straight back to its costly full-detail state as soon as the finger was
    // lifted. `configureFramePressure` has hysteresis and restores quality
    // only after a healthy measurement window; essential OSM evidence is
    // never affected by this tier.
  }

  /// IndexedStack keeps the map state mounted while another tab is visible.
  /// Shared animation clocks use this flag to avoid repainting an unseen map.
  static bool get mapVisible => _mapVisible;

  static void setMapVisible(bool value) {
    _mapVisible = value;
    ambientClock.setVisible(value);
    actorClock.setVisible(value);
  }

  /// When the map has been still for a few seconds, keep water alive at a
  /// calmer two-frame cadence. This avoids waking the raster thread three
  /// times per second while a phone is simply lying in a pocket-mounted
  /// holder, without making rivers and lakes look permanently frozen.
  ///
  /// The active pressure tier always wins: a struggling device can ask for
  /// an even slower cadence, but idle mode never removes mapped water or its
  /// static texture.
  static bool get ambientIdle => _ambientIdle;

  static void setAmbientIdle(bool value) {
    if (_ambientIdle == value) return;
    _ambientIdle = value;
    _applyAmbientTickDivisor();
  }

  static void _applyAmbientTickDivisor() {
    ambientClock.setTickDivisor(
      math.max(_frameAmbientTickDivisor, _ambientIdle ? 2 : 1),
    );
  }

  /// One deliberately stepped clock shared by every ambient map animation.
  ///
  /// Previously water polygons, waterways and flowers each owned a periodic
  /// timer. Their out-of-phase callbacks could keep a large portion of the
  /// map repainting almost continuously even while the hiker stood still.
  /// Four synchronised frames per second preserve the pixel-art motion while
  /// giving the raster and CPU threads long idle windows.
  static final MapAnimationClock ambientClock = MapAnimationClock._(
    step: const Duration(milliseconds: 333),
    phaseIncrement: 1 / 16,
  );

  /// Shared 20 fps clock for Bit and GNSS interpolation. This avoids tying
  /// sprite work to a phone's 60/90/120 Hz display refresh rate.
  static final MapAnimationClock actorClock = MapAnimationClock._(
    step: const Duration(milliseconds: 50),
    phaseIncrement: 1 / 20,
  );

  static void setAppActive(bool value) {
    ambientClock.setAppActive(value);
    actorClock.setAppActive(value);
  }

  /// Bit needs display-like updates only while walking or easing a meaningful
  /// GNSS displacement. The map-reading animation advances at 2 fps, so
  /// keeping the actor clock at 20 fps while the hiker rests merely wakes the
  /// UI isolate and drains battery without changing a pixel.
  static void setActorWalking(bool value) {
    if (_actorWalking != value) _actorWalking = value;
    _applyActorTickDivisor();
  }

  /// A short interpolation after a new GPS fix temporarily takes priority
  /// over the idle animation cadence. WildBit has one rendered actor, so a
  /// boolean is sufficient and avoids retaining separate animation timers.
  static void setActorInterpolating(bool value) {
    if (_actorInterpolating != value) _actorInterpolating = value;
    _applyActorTickDivisor();
  }

  static void _applyActorTickDivisor() {
    actorClock.setTickDivisor(_actorWalking || _actorInterpolating ? 1 : 10);
  }

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

  /// Paint-time cap for long OSM waterways. The centerline and endpoints
  /// remain present; only redundant intermediate samples are reduced.
  static int waterwayMaximumPoints(double zoom) {
    final normal = zoom >= 15
        ? 2048
        : zoom >= 11
        ? 1024
        : 512;
    return _mapInteracting ? math.min(normal, 384) : normal;
  }

  /// Paint-time cap for the recorded user track. The original fixes are
  /// retained verbatim by the recorder; this only bounds the temporary screen
  /// geometry while the map is moving. Both endpoints are preserved by the
  /// line projector, so Bit's current position and the origin remain exact.
  static int recordedTrackMaximumPoints(double zoom) {
    final normal = zoom >= 14 ? 2048 : 768;
    return _mapInteracting ? math.min(normal, 384) : normal;
  }

  /// A moving camera already supplies continuous motion, so the pixel track
  /// can safely use a slightly coarser screen-space simplification until the
  /// gesture settles. This avoids projection work proportional to a long
  /// recording on mid-range phones.
  static double recordedTrackPointDistancePixels(double zoom) {
    final normal = ((18 - zoom) * .45).clamp(1.2, 5.0).toDouble();
    return _mapInteracting ? math.max(normal, 3.2) : normal;
  }

  /// Contours are supporting terrain context. Keep a stable bounded set on
  /// dense elevation sources, then reduce only intermediate samples while the
  /// camera moves. This preserves the relief read without allowing contour
  /// imports to dominate the frame budget on a phone.
  static int contourPaintLimit(double zoom) {
    final normal = zoom >= 15 ? 96 : 48;
    return _mapInteracting ? math.min(normal, 32) : normal;
  }

  static int contourMaximumPoints(double zoom) {
    final normal = zoom >= 14 ? 1024 : 512;
    return _mapInteracting ? math.min(normal, 256) : normal;
  }

  static double contourPointDistancePixels(double zoom) {
    final normal = zoom >= 15 ? 3.0 : 4.5;
    return _mapInteracting ? math.max(normal, 5.5) : normal;
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
    final quality = decorativeQuality;
    final adjustedOverview = math.max(1, (overview * quality).round());
    final adjustedClose = math.max(adjustedOverview, (close * quality).round());
    if (zoom <= overviewZoom) return adjustedOverview;
    final t = ((zoom - overviewZoom) / (closeZoom - overviewZoom)).clamp(
      0.0,
      1.0,
    );
    final progressive =
        (adjustedOverview + (adjustedClose - adjustedOverview) * t).round();
    return progressive;
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
    final quality = decorativeQuality;
    final adjustedOverview = math.max(1, (overview * quality).round());
    final adjustedClose = math.max(adjustedOverview, (close * quality).round());
    if (bands < 1 || close <= overview) return adjustedOverview;
    if (zoom <= overviewZoom) return adjustedOverview;
    final t = ((zoom - overviewZoom) / (closeZoom - overviewZoom)).clamp(
      0.0,
      1.0,
    );
    final bucket = (t * bands).round() / bands;
    final target =
        (adjustedOverview + (adjustedClose - adjustedOverview) * bucket)
            .round();
    return target;
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
    PoiType.ford => 0,
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
    PoiType.ford => 14,
  };

  /// Paint budget for point markers. Priority POIs are exempt in the layer;
  /// this cap applies only to secondary orientation markers at overview zoom.
  static int poiPaintLimit(double zoom) {
    final normal = zoom < 10
        ? 64
        : zoom < 13
        ? 128
        : zoom < 15
        ? 220
        : 420;
    // Priority POIs are exempt in the layer.  This only shrinks secondary
    // marker work under sustained frame pressure.
    return math.max(24, (normal * decorativeQuality).round());
  }

  /// City footprints are orientation decoration; trail evidence is handled
  /// by separate layers. During a gesture they are deliberately a very small
  /// stable sample: a city must not steal the frame budget from the terrain,
  /// trail and GPS marker the hiker is actively following. At rest the
  /// complete local-orientation budget is restored.
  static int urbanPaintLimit() {
    final normal = mapInteracting ? 24 : 120;
    final floor = mapInteracting ? 8 : 20;
    return math.max(floor, (normal * decorativeQuality).round());
  }

  static bool areaMayBeVisible(AreaFeature area, LatLngBounds viewport) {
    final extent = _areaExtents[area] ??= _GeographicExtent.from(area.ring);
    return extent.overlaps(viewport);
  }

  static bool lineMayBeVisible(LineFeature line, LatLngBounds viewport) {
    final extent = _lineExtents[line] ??= _GeographicExtent.from(line.points);
    return extent.overlaps(viewport);
  }

  /// Paint-time visibility check for composed geometry that no longer has a
  /// one-to-one [LineFeature] identity (for example a river stroke assembled
  /// from several OSM ways). The caller owns the source list, so this helper
  /// deliberately does not retain an [Expando] entry for the temporary ring.
  static bool pointsMayBeVisible(
    Iterable<LatLng> points,
    LatLngBounds viewport,
  ) {
    final coordinates = points is List<LatLng>
        ? points
        : points.toList(growable: false);
    return _GeographicExtent.from(coordinates).overlaps(viewport);
  }

  /// Returns true when two longitude intervals overlap, including intervals
  /// that wrap from +180° to -180°. OSM extracts around the antimeridian must
  /// not be culled as if their west edge were numerically smaller than east.
  static bool longitudeIntervalsOverlap(
    double firstWest,
    double firstEast,
    double secondWest,
    double secondEast, {
    double margin = 0,
  }) {
    final first = _longitudeRanges(firstWest, firstEast, margin: margin);
    final second = _longitudeRanges(secondWest, secondEast, margin: margin);
    for (final a in first) {
      for (final b in second) {
        if (a.west <= b.east && b.west <= a.east) return true;
      }
    }
    return false;
  }

  /// True when the second interval is fully covered by the first one.
  static bool longitudeIntervalContains(
    double outerWest,
    double outerEast,
    double innerWest,
    double innerEast,
  ) {
    final outer = _longitudeRanges(outerWest, outerEast);
    final inner = _longitudeRanges(innerWest, innerEast);
    return inner.every(
      (inside) => outer.any(
        (container) =>
            container.west <= inside.west && container.east >= inside.east,
      ),
    );
  }

  static List<({double west, double east})> _longitudeRanges(
    double west,
    double east, {
    double margin = 0,
  }) {
    final span = east - west < 0 ? east - west + 360 : east - west;
    if (span >= 360 - 1e-9) {
      return const [(west: -180, east: 180)];
    }
    final wraps = west > east;
    final start = _normalizeLongitude(west - margin);
    final end = _normalizeLongitude(east + margin);
    if (!wraps && start <= end) return [(west: start, east: end)];
    if (wraps && start > end) {
      return [(west: start, east: 180), (west: -180, east: end)];
    }
    // A margin can make a very small wrapped interval touch both poles of the
    // coordinate domain. Treat the resulting interval conservatively.
    return [(west: math.min(start, end), east: math.max(start, end))];
  }

  static double _normalizeLongitude(double value) {
    var normalized = value;
    while (normalized < -180) {
      normalized += 360;
    }
    while (normalized > 180) {
      normalized -= 360;
    }
    return normalized;
  }
}

class MapAnimationClock extends ChangeNotifier {
  MapAnimationClock._({required this._step, required this._phaseIncrement});

  final Duration _step;
  final double _phaseIncrement;
  Timer? _timer;
  int _listeners = 0;
  bool _visible = true;
  bool _appActive = true;
  bool _suspended = false;
  int _tickDivisor = 1;
  double _phase = 0;

  double get phase => _phase;

  @visibleForTesting
  int get tickDivisor => _tickDivisor;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listeners++;
    _updateTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners = math.max(0, _listeners - 1);
    _updateTimer();
  }

  void setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    _updateTimer();
  }

  void setAppActive(bool value) {
    if (_appActive == value) return;
    _appActive = value;
    _updateTimer();
  }

  void setSuspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    _updateTimer();
  }

  void setTickDivisor(int value) {
    final next = math.max(1, value);
    if (_tickDivisor == next) return;
    _tickDivisor = next;
    // A periodic Timer retains its original period. Cancel it explicitly so
    // quality pressure changes take effect now rather than only after a tab
    // switch, lifecycle transition or later gesture suspension.
    _timer?.cancel();
    _timer = null;
    _updateTimer();
  }

  void _updateTimer() {
    final shouldRun = _visible && _appActive && !_suspended && _listeners > 0;
    if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer?.isActive ?? false) return;
    final step = Duration(microseconds: _step.inMicroseconds * _tickDivisor);
    _timer = Timer.periodic(step, (_) {
      _phase = (_phase + _phaseIncrement) % 1;
      notifyListeners();
    });
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
    if (east - west > 180) {
      final wrappedWest = east;
      east = west;
      west = wrappedWest;
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
        MapRenderingBudget.longitudeIntervalsOverlap(
          west,
          east,
          viewport.west,
          viewport.east,
          margin: margin,
        );
  }
}
