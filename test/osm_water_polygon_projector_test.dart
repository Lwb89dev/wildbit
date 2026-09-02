import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/osm_water_polygon_projector.dart';
import 'package:wildbit/map_rendering/composition/osm_line_projector.dart';

void main() {
  const lake = AreaFeature(
    kind: MapFeatureKind.water,
    ring: [LatLng(46, 11), LatLng(46, 11.01), LatLng(45.99, 11.01)],
  );

  test('projects OSM geographic rings through the supplied map projection', () {
    final polygon = OsmWaterPolygonProjector.project(
      lake,
      (point) => Offset(point.longitude * 100, point.latitude * -100),
    );
    expect(polygon, const [
      Offset(1100, -4600),
      Offset(1101, -4600),
      Offset(1101, -4599),
    ]);
  });

  test('derives a stable seed from OSM geometry', () {
    expect(
      OsmWaterPolygonProjector.seedFor(lake),
      OsmWaterPolygonProjector.seedFor(lake),
    );
  });

  test('removes only invisible ring detail while retaining a sharp inlet', () {
    final ring = [
      for (var x = 0; x <= 20; x++) LatLng(0, x / 10000),
      const LatLng(.001, .002),
      const LatLng(.001, 0),
    ];

    final projected = OsmWaterPolygonProjector.projectRing(
      ring,
      (point) => Offset(point.longitude * 1000, point.latitude * -1000),
      minimumDistancePixels: 1,
    );

    expect(projected.length, lessThan(ring.length));
    expect(projected, contains(const Offset(2, -1)));
    expect(projected, contains(const Offset(0, -1)));
  });

  test('does not project every pathological intermediate OSM vertex', () {
    final points = [
      for (var index = 0; index < 50000; index++)
        LatLng(46 + index * .0000001, 11 + index * .0000001),
    ];
    final projected = OsmLineProjector.projectSimplifiedPoints(
      points,
      (point) => Offset(point.longitude * 1000, point.latitude * -1000),
      minimumDistancePixels: 2.5,
      maximumPoints: 384,
    );

    expect(projected.length, lessThanOrEqualTo(384));
    expect(projected.first, const Offset(11000, -46000));
    expect(projected.last.dx, closeTo(11004.9999, .000001));
    expect(projected.last.dy, closeTo(-46004.9999, .000001));
  });
}
