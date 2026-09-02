import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
import 'mixed_preview_region.dart';

/// Dense, deterministic local scene for renderer profiling.
///
/// It intentionally resembles an over-detailed OSM viewport: a large number
/// of individually mapped trees, small building footprints and contours. It
/// is not navigational data and never ships as a normal map fallback.
final MapFeatureCollection rendererStressFeatures = MapFeatureCollection(
  areas: [
    ...mixedPreviewFeatures.areas,
    for (var index = 0; index < 320; index++) _building(index),
  ],
  lines: [
    ...mixedPreviewFeatures.lines,
    for (var index = 0; index < 180; index++) _contour(index),
  ],
  pois: [
    ...mixedPreviewFeatures.pois,
    for (var index = 0; index < 1200; index++)
      Poi(
        id: 'stress-tree-$index',
        name: 'Albero test',
        type: PoiType.tree,
        position: _position(index, latitude: 46.0585, longitude: 11.1095),
      ),
  ],
);

AreaFeature _building(int index) {
  final anchor = _position(index, latitude: 46.0590, longitude: 11.1110);
  final latitudeSize = .00004 + (index % 3) * .000015;
  final longitudeSize = .00005 + (index % 4) * .000015;
  return AreaFeature(
    kind: MapFeatureKind.building,
    sourceId: 'stress-building-$index',
    ring: [
      anchor,
      LatLng(anchor.latitude, anchor.longitude + longitudeSize),
      LatLng(anchor.latitude + latitudeSize, anchor.longitude + longitudeSize),
      LatLng(anchor.latitude + latitudeSize, anchor.longitude),
    ],
  );
}

LineFeature _contour(int index) {
  final latitude = 46.058 + index * .000085;
  final bend = (index % 7) * .00011;
  return LineFeature(
    kind: MapFeatureKind.contourLine,
    name: 'Quota test ${1000 + index * 5}',
    points: [
      LatLng(latitude, 11.108),
      LatLng(latitude + .00035, 11.115 + bend),
      LatLng(latitude - .00015, 11.122 - bend),
      LatLng(latitude + .00025, 11.132),
    ],
  );
}

LatLng _position(
  int index, {
  required double latitude,
  required double longitude,
}) {
  // Stable pseudo-random spread: no runtime Random instance and no regular
  // plantation grid which would hide projection/culling errors.
  var value = index * 1103515245 + 12345;
  value = (value ^ (value >> 16)) & 0x7fffffff;
  final latitudeOffset = (value % 10000) / 10000 * .018;
  value = (value * 1664525 + 1013904223) & 0x7fffffff;
  final longitudeOffset = (value % 10000) / 10000 * .024;
  return LatLng(latitude + latitudeOffset, longitude + longitudeOffset);
}
