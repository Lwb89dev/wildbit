import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';
import 'package:wildbit/map_rendering/composition/map_geometry_rules.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';

void main() {
  const lake = AreaFeature(
    kind: MapFeatureKind.water,
    ring: [
      LatLng(45, 10),
      LatLng(45, 11),
      LatLng(46, 11),
      LatLng(46, 10),
    ],
    sourceId: 'lake-1',
  );

  test('classifies points inside and outside a water polygon', () {
    expect(
      MapGeometryRules.pointInPolygon(const LatLng(45.5, 10.5), lake.ring),
      isTrue,
    );
    expect(
      MapGeometryRules.pointInPolygon(const LatLng(46.5, 10.5), lake.ring),
      isFalse,
    );
  });

  test('rejects objects inside any water area', () {
    expect(
      MapGeometryRules.insideAnyWater(
        const LatLng(45.25, 10.25),
        [lake],
      ),
      isTrue,
    );
    expect(
      MapGeometryRules.insideAnyWater(
        const LatLng(44.9, 10.25),
        [lake],
      ),
      isFalse,
    );
  });

  test('ranks larger geographic polygons first', () {
    expect(
      MapGeometryRules.polygonArea(lake.ring),
      greaterThan(0),
    );
  });

  test('detects the transition band along polygon boundaries', () {
    expect(
      MapGeometryRules.nearPolygonBoundary(
        const LatLng(45.0001, 10.5),
        lake.ring,
        thresholdDegrees: .0002,
      ),
      isTrue,
    );
    expect(
      MapGeometryRules.nearPolygonBoundary(
        const LatLng(45.5, 10.5),
        lake.ring,
        thresholdDegrees: .0002,
      ),
      isFalse,
    );
  });

  test('keeps decorative sprites readable across zoom extremes', () {
    expect(
      MapRenderingBudget.decorativeScale(3),
      closeTo(.28, 0.001),
    );
    expect(
      MapRenderingBudget.decorativeScale(16),
      closeTo(1, 0.001),
    );
    expect(
      MapRenderingBudget.decorativeScale(22),
      closeTo(1.3, 0.001),
    );
  });

  test('uses deterministic progressive decorative density', () {
    expect(
      MapRenderingBudget.decorativeCount(8, overview: 20, close: 100),
      20,
    );
    expect(
      MapRenderingBudget.decorativeCount(11.5, overview: 20, close: 100),
      60,
    );
    expect(
      MapRenderingBudget.decorativeCount(15, overview: 20, close: 100),
      100,
    );
  });

  test('keeps biomes visually distinct', () {
    expect(
      MapRenderingBudget.biomeDensity(MapFeatureKind.forest),
      greaterThan(MapRenderingBudget.biomeDensity(MapFeatureKind.meadow)),
    );
    expect(
      MapRenderingBudget.biomeDensity(MapFeatureKind.park),
      greaterThan(MapRenderingBudget.biomeDensity(MapFeatureKind.meadow)),
    );
  });

  test('gives shelters a stronger silhouette than minor POIs', () {
    expect(
      MapRenderingBudget.poiMarkerSize(PoiType.shelter, 16),
      greaterThan(MapRenderingBudget.poiMarkerSize(PoiType.campsite, 16)),
    );
    expect(
      MapRenderingBudget.poiMarkerSize(PoiType.shelter, 3),
      greaterThanOrEqualTo(15),
    );
  });
}
