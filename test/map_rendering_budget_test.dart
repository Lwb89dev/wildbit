import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';

void main() {
  tearDown(() {
    MapRenderingBudget.resetDeviceProfile();
    MapRenderingBudget.setMapInteracting(false);
    MapRenderingBudget.setMapVisible(true);
    MapRenderingBudget.resetFramePressure();
    MapRenderingBudget.configureScene(
      const MapFeatureCollection(areas: [], lines: [], pois: []),
    );
  });

  test(
    'keeps sprite population stable but lowers route work during gestures',
    () {
      final normalDecorative = MapRenderingBudget.decorativeCount(
        15,
        overview: 4,
        close: 100,
      );
      final normalRoutes = MapRenderingBudget.routeMaximumPoints(
        _fakeTrail,
        16,
      );

      MapRenderingBudget.setMapInteracting(true);
      expect(
        MapRenderingBudget.decorativeCount(15, overview: 4, close: 100),
        normalDecorative,
      );
      expect(
        MapRenderingBudget.routeMaximumPoints(_fakeTrail, 16),
        lessThan(normalRoutes),
      );

      MapRenderingBudget.setMapInteracting(false);
      expect(
        MapRenderingBudget.decorativeCount(15, overview: 4, close: 100),
        normalDecorative,
      );
      expect(MapRenderingBudget.mapInteracting, isFalse);
    },
  );

  test('keeps quantised sprite LOD stable across interaction boundaries', () {
    final idle = MapRenderingBudget.decorativeLodCount(
      13.2,
      overview: 20,
      close: 160,
    );
    MapRenderingBudget.setMapInteracting(true);
    final moving = MapRenderingBudget.decorativeLodCount(
      13.2,
      overview: 20,
      close: 160,
    );
    expect(moving, idle);
  });

  test('keeps decorative LOD density stable inside a zoom band', () {
    final first = MapRenderingBudget.decorativeLodCount(
      10.1,
      overview: 20,
      close: 100,
    );
    final second = MapRenderingBudget.decorativeLodCount(
      10.4,
      overview: 20,
      close: 100,
    );
    expect(second, first);
    expect(
      MapRenderingBudget.decorativeLodCount(15, overview: 20, close: 100),
      100,
    );
  });

  test('tracks whether the mounted map tab is visible', () {
    expect(MapRenderingBudget.mapVisible, isTrue);
    MapRenderingBudget.setMapVisible(false);
    expect(MapRenderingBudget.mapVisible, isFalse);
  });

  test(
    'starts dense render surfaces with a conservative decorative budget',
    () {
      MapRenderingBudget.configureDevice(
        logicalWidth: 360,
        logicalHeight: 800,
        devicePixelRatio: 3,
      );
      final phoneQuality = MapRenderingBudget.decorativeQuality;

      MapRenderingBudget.configureDevice(
        logicalWidth: 1280,
        logicalHeight: 800,
        devicePixelRatio: 2,
      );
      final tabletQuality = MapRenderingBudget.decorativeQuality;

      expect(phoneQuality, closeTo(.78, .001));
      expect(tabletQuality, lessThan(phoneQuality));
    },
  );

  test('adapts only decorative quality to measured frame pressure', () {
    expect(
      MapRenderingBudget.configureFramePressure(
        averageBuildMicros: 32000,
        averageRasterMicros: 28000,
      ),
      isTrue,
    );
    expect(MapRenderingBudget.decorativeQuality, lessThan(1));
    expect(
      MapRenderingBudget.configureFramePressure(
        averageBuildMicros: 8000,
        averageRasterMicros: 9000,
      ),
      isTrue,
    );
    expect(MapRenderingBudget.decorativeQuality, 1);
    expect(
      MapRenderingBudget.configureFramePressure(
        averageBuildMicros: 8000,
        averageRasterMicros: 9000,
      ),
      isFalse,
    );
  });

  test('keeps a degraded tier through borderline recovery samples', () {
    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 32000,
      averageRasterMicros: 28000,
    );
    expect(MapRenderingBudget.framePressureLevel, 3);

    // A frame just under budget is not enough evidence to rebuild all
    // decorative layers again; the severe tier stays in place until the p95
    // equivalent has meaningful room below the 16.7 ms target.
    expect(
      MapRenderingBudget.configureFramePressure(
        averageBuildMicros: 16000,
        averageRasterMicros: 16000,
      ),
      isFalse,
    );
    expect(MapRenderingBudget.framePressureLevel, 3);
    expect(MapRenderingBudget.decorativeQuality, closeTo(.35, .001));

    // A genuinely healthy sample can return to full detail immediately.
    expect(
      MapRenderingBudget.configureFramePressure(
        averageBuildMicros: 9000,
        averageRasterMicros: 9000,
      ),
      isTrue,
    );
    expect(MapRenderingBudget.framePressureLevel, 0);
    expect(MapRenderingBudget.decorativeQuality, 1);
  });

  test('keeps the measured decorative tier when a camera gesture ends', () {
    MapRenderingBudget.setMapInteracting(true);
    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 40000,
      averageRasterMicros: 40000,
    );
    expect(MapRenderingBudget.framePressureLevel, 3);

    MapRenderingBudget.setMapInteracting(false);

    expect(MapRenderingBudget.framePressureLevel, 3);
    expect(MapRenderingBudget.decorativeQuality, closeTo(.35, .001));
  });

  test('uses p95 pressure even when the average stages look healthy', () {
    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 7000,
      averageRasterMicros: 8000,
      p95FrameMicros: 26000,
    );

    expect(MapRenderingBudget.framePressureLevel, 3);
    expect(MapRenderingBudget.decorativeQuality, closeTo(.35, .001));
  });

  test('changes the ambient clock divisor under frame pressure', () {
    expect(MapRenderingBudget.ambientClock.tickDivisor, 1);

    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 40000,
      averageRasterMicros: 40000,
    );
    expect(MapRenderingBudget.ambientClock.tickDivisor, 3);

    MapRenderingBudget.resetFramePressure();
    expect(MapRenderingBudget.ambientClock.tickDivisor, 1);
  });

  test('uses a calmer ambient cadence after the map has settled', () {
    expect(MapRenderingBudget.ambientClock.tickDivisor, 1);

    MapRenderingBudget.setAmbientIdle(true);
    expect(MapRenderingBudget.ambientIdle, isTrue);
    expect(MapRenderingBudget.ambientClock.tickDivisor, 2);

    // A pressure tier remains authoritative, so a slow device is never
    // accidentally made more expensive merely because the map is idle.
    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 40000,
      averageRasterMicros: 40000,
    );
    expect(MapRenderingBudget.ambientClock.tickDivisor, 3);

    MapRenderingBudget.setMapInteracting(true);
    expect(MapRenderingBudget.ambientIdle, isFalse);
    expect(MapRenderingBudget.ambientClock.tickDivisor, 3);
  });

  test('degrades shore modules and ambient detail before map evidence', () {
    final normalShore = MapRenderingBudget.shoreDetailCount(18);
    expect(MapRenderingBudget.ambientDetailEnabled, isTrue);

    MapRenderingBudget.configureFramePressure(
      averageBuildMicros: 40000,
      averageRasterMicros: 40000,
    );

    expect(MapRenderingBudget.shoreDetailCount(18), lessThan(normalShore));
    expect(MapRenderingBudget.shoreDetailCount(18), greaterThanOrEqualTo(4));
    expect(MapRenderingBudget.ambientDetailEnabled, isFalse);
  });

  test('caps only intermediate waterway detail during gestures', () {
    expect(MapRenderingBudget.waterwayMaximumPoints(16), 2048);
    MapRenderingBudget.setMapInteracting(true);
    expect(MapRenderingBudget.waterwayMaximumPoints(16), 384);
    expect(MapRenderingBudget.waterwayMaximumPoints(9), 384);
  });

  test('reduces only temporary recorded-track detail during gestures', () {
    final normalPoints = MapRenderingBudget.recordedTrackMaximumPoints(16);
    final normalDistance = MapRenderingBudget.recordedTrackPointDistancePixels(
      16,
    );

    MapRenderingBudget.setMapInteracting(true);

    expect(
      MapRenderingBudget.recordedTrackMaximumPoints(16),
      lessThan(normalPoints),
    );
    expect(
      MapRenderingBudget.recordedTrackMaximumPoints(16),
      greaterThanOrEqualTo(2),
    );
    expect(
      MapRenderingBudget.recordedTrackPointDistancePixels(16),
      greaterThanOrEqualTo(normalDistance),
    );
  });

  test('keeps a bounded contour set while simplifying during gestures', () {
    final normalLimit = MapRenderingBudget.contourPaintLimit(16);
    final normalPoints = MapRenderingBudget.contourMaximumPoints(16);
    final normalDistance = MapRenderingBudget.contourPointDistancePixels(16);

    MapRenderingBudget.setMapInteracting(true);

    expect(MapRenderingBudget.contourPaintLimit(16), lessThan(normalLimit));
    expect(MapRenderingBudget.contourMaximumPoints(16), lessThan(normalPoints));
    expect(
      MapRenderingBudget.contourPointDistancePixels(16),
      greaterThan(normalDistance),
    );
  });

  test('keeps longitude culling continuous at the antimeridian', () {
    expect(
      MapRenderingBudget.longitudeIntervalsOverlap(179.8, -179.8, -180, -179.7),
      isTrue,
    );
    expect(
      MapRenderingBudget.longitudeIntervalsOverlap(179.8, -179.8, -10, 10),
      isFalse,
    );
    expect(
      MapRenderingBudget.longitudeIntervalContains(
        179.5,
        -179.5,
        179.7,
        -179.7,
      ),
      isTrue,
    );
  });

  test('culls composed point chains across the antimeridian', () {
    final crossing = [const LatLng(10, 179.8), const LatLng(10.1, -179.8)];
    final localBounds = LatLngBounds(
      const LatLng(9.9, 179.7),
      const LatLng(10.2, 179.95),
    );
    expect(
      MapRenderingBudget.pointsMayBeVisible(crossing, localBounds),
      isTrue,
    );
  });

  test('uses a bounded marker budget at overview zooms', () {
    expect(MapRenderingBudget.poiPaintLimit(9), 64);
    expect(MapRenderingBudget.poiPaintLimit(12), 128);
    expect(MapRenderingBudget.poiPaintLimit(14), 220);
    expect(MapRenderingBudget.poiPaintLimit(16), 420);
  });

  test('accounts for dense source geometry in the scene quality budget', () {
    final denseContour = LineFeature(
      kind: MapFeatureKind.contourLine,
      points: List<LatLng>.generate(
        14000,
        (index) => LatLng(45 + index / 1e8, 9 + index / 1e8),
      ),
    );
    MapRenderingBudget.configureScene(
      MapFeatureCollection(
        areas: const [],
        lines: [denseContour],
        pois: const [],
      ),
    );

    expect(MapRenderingBudget.decorativeQuality, closeTo(.84, .001));
  });
}

// The budget only reads kind and route metadata; keeping this test focused on
// the public budget API avoids coupling it to a renderer widget.
const _fakeTrail = LineFeature(
  kind: MapFeatureKind.trail,
  points: [LatLng(46, 11), LatLng(46.001, 11.001)],
);
