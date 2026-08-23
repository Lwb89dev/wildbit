import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/entities/trail_classification.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/osm_line_projector.dart';
import 'package:wildbit/map_rendering/composition/route_visual_style.dart';

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
}
