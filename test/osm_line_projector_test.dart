import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/entities/trail_classification.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/osm_line_projector.dart';
import 'package:wildbit/map_rendering/composition/route_visual_style.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';

void main() {
  const trail = LineFeature(
    kind: MapFeatureKind.trail,
    points: [LatLng(46, 11), LatLng(46.01, 11.02)],
  );

  test('projects an OSM line through the map projection', () {
    final points = OsmLineProjector.project(
      trail,
      (point) => Offset(point.longitude * 10, point.latitude * -10),
    );
    expect(points.first, const Offset(110, -460));
    expect(points.last.dx, closeTo(110.2, .000001));
    expect(points.last.dy, closeTo(-460.1, .000001));
  });

  test('keeps the visual variant seed stable', () {
    expect(OsmLineProjector.seedFor(trail), OsmLineProjector.seedFor(trail));
  });

  test('reuses projected geometry within one camera view', () {
    final cache = ProjectedLineCache();
    cache.beginView('view-a');
    final first = cache.project(
      trail,
      (point) => Offset(point.longitude * 10, point.latitude * -10),
      minimumDistancePixels: 2,
      maximumPoints: 64,
    );
    final second = cache.project(
      trail,
      (point) => Offset(point.longitude * 10, point.latitude * -10),
      minimumDistancePixels: 2,
      maximumPoints: 64,
    );
    expect(identical(first, second), isTrue);
    expect(cache.length, 1);
    expect(cache.hits, 1);
    expect(cache.misses, 1);
    expect(cache.hitRate, .5);
  });

  test('caps pathological geometry while preserving endpoints', () {
    final points = [
      for (var index = 0; index < 100; index++) Offset(index.toDouble(), 0),
    ];
    final capped = OsmLineProjector.capPoints(points, maximumPoints: 10);
    expect(capped, hasLength(10));
    expect(capped.first, points.first);
    expect(capped.last, points.last);
  });

  test('culls projected lines outside the viewport', () {
    expect(
      OsmLineProjector.overlapsViewport([
        const Offset(-100, -100),
        const Offset(-50, -50),
      ], const Size(40, 40)),
      isFalse,
    );
    expect(
      OsmLineProjector.overlapsViewport([
        const Offset(-10, 20),
        const Offset(20, 20),
      ], const Size(40, 40)),
      isTrue,
    );
  });

  test('preserves a close sharp turn while simplifying a route', () {
    const bent = LineFeature(
      kind: MapFeatureKind.trail,
      points: [
        LatLng(0, 0),
        LatLng(0, .00001),
        LatLng(.00001, .00001),
        LatLng(.01, .00001),
      ],
    );
    final points = OsmLineProjector.projectSimplified(
      bent,
      (point) => Offset(point.longitude * 1000, -point.latitude * 1000),
      minimumDistancePixels: 5,
    );

    expect(
      points.any((point) => (point - const Offset(.01, 0)).distance < .000001),
      isTrue,
    );
  });

  test('keeps important numbered routes more geometrically detailed', () {
    const ordinary = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(0, .001), LatLng(.001, .001)],
    );
    const numbered = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(0, .001), LatLng(.001, .001)],
      metadata: RouteMetadata(ref: 'E5'),
    );

    expect(
      MapRenderingBudget.routePointDistancePixels(numbered, 8),
      lessThan(MapRenderingBudget.routePointDistancePixels(ordinary, 8)),
    );
  });

  test('distinguishes paved roads, forest tracks and trails', () {
    const paved = LineFeature(
      kind: MapFeatureKind.road,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(surface: 'asphalt'),
    );
    const track = LineFeature(
      kind: MapFeatureKind.road,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(surface: 'gravel'),
    );

    expect(
      RouteVisualStyle.forLine(paved, 16).family,
      RouteTextureFamily.paved,
    );
    expect(
      RouteVisualStyle.forLine(track, 16).family,
      RouteTextureFamily.track,
    );
    expect(
      RouteVisualStyle.forLine(trail, 16).family,
      RouteTextureFamily.trail,
    );
  });

  test('exposes exact trail safety styling without hiding the geometry', () {
    const technicalTrail = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(
        sacScale: 'alpine_hiking',
        trailVisibility: 'bad',
        footAccess: 'no',
      ),
    );

    final style = RouteVisualStyle.forLine(technicalTrail, 16);

    expect(style.family, RouteTextureFamily.trail);
    expect(style.difficulty, TrailDifficulty.t4);
    expect(style.difficultyColor, isNotNull);
    expect(style.access, TrailAccessStatus.restricted);
    expect(style.visibility, TrailVisibilityStatus.reduced);
    expect(style.width, greaterThan(0));
  });

  test('selects obstacle and surface textures from explicit OSM tags', () {
    const steps = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(highwayTag: 'steps'),
    );
    const ford = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(fordTag: 'yes'),
    );
    const mud = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(surface: 'mud'),
    );

    expect(RouteVisualStyle.forLine(steps, 16).family, RouteTextureFamily.rock);
    expect(RouteVisualStyle.forLine(ford, 16).family, RouteTextureFamily.ford);
    expect(RouteVisualStyle.forLine(mud, 16).family, RouteTextureFamily.sand);
  });

  test('marks explicit tunnels and via ferrata as technical geometry', () {
    const viaFerrata = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(0, 0), LatLng(1, 1)],
      metadata: RouteMetadata(
        highwayTag: 'via_ferrata',
        tunnelTag: 'yes',
        accessConditional: 'no @ (winter)',
      ),
    );

    final style = RouteVisualStyle.forLine(viaFerrata, 16);

    expect(style.family, RouteTextureFamily.rock);
    expect(style.isTunnel, isTrue);
    expect(style.isConditional, isTrue);
  });
}
