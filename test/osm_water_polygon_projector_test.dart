import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/osm_water_polygon_projector.dart';

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
}
