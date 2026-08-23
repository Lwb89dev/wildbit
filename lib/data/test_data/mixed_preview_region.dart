import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
import 'test_region.dart';

/// Offline showcase fixture containing every visual category in one valley.
final MapFeatureCollection mixedPreviewFeatures = MapFeatureCollection(
  areas: [
    ...testRegionFeatures.areas,
    const AreaFeature(
      kind: MapFeatureKind.building,
      sourceId: 'mixed-lodge',
      ring: [
        LatLng(46.0680, 11.1200),
        LatLng(46.0680, 11.1210),
        LatLng(46.0688, 11.1210),
        LatLng(46.0688, 11.1200),
      ],
    ),
    const AreaFeature(
      kind: MapFeatureKind.building,
      sourceId: 'mixed-cabin',
      ring: [
        LatLng(46.0648, 11.1270),
        LatLng(46.0648, 11.1278),
        LatLng(46.0655, 11.1278),
        LatLng(46.0655, 11.1270),
      ],
    ),
  ],
  lines: [
    ...testRegionFeatures.lines,
    const LineFeature(
      kind: MapFeatureKind.contourLine,
      name: 'Quota 1200',
      points: [
        LatLng(46.0630, 11.1160),
        LatLng(46.0617, 11.1200),
        LatLng(46.0612, 11.1250),
        LatLng(46.0618, 11.1300),
      ],
    ),
    const LineFeature(
      kind: MapFeatureKind.contourLine,
      name: 'Quota 1300',
      points: [
        LatLng(46.0616, 11.1168),
        LatLng(46.0603, 11.1205),
        LatLng(46.0598, 11.1250),
        LatLng(46.0604, 11.1290),
      ],
    ),
    const LineFeature(
      kind: MapFeatureKind.contourLine,
      name: 'Quota 1400',
      points: [
        LatLng(46.0600, 11.1180),
        LatLng(46.0589, 11.1215),
        LatLng(46.0584, 11.1250),
        LatLng(46.0591, 11.1280),
      ],
    ),
    const LineFeature(
      kind: MapFeatureKind.trail,
      name: 'Ponte del Bosco',
      nodeIds: ['bridge-a', 'bridge-b'],
      metadata: RouteMetadata(
        osmWayId: 'mixed-bridge',
        bridgeTag: 'yes',
        bridgeStructure: 'wood',
      ),
      points: [LatLng(46.0668, 11.1240), LatLng(46.0668, 11.1260)],
    ),
  ],
  pois: [
    ...testRegionFeatures.pois,
    for (var i = 0; i < 180; i++)
      Poi(
        id: 'mixed-tree-$i',
        name: 'Albero del bosco',
        type: PoiType.tree,
        position: _forestTreePosition(i),
      ),
    const Poi(
      id: 'mixed-summit',
      name: 'Cima panoramica',
      type: PoiType.summit,
      position: LatLng(46.0605, 11.1250),
    ),
    const Poi(
      id: 'mixed-water',
      name: 'Fonte del sentiero',
      type: PoiType.waterSource,
      position: LatLng(46.0675, 11.1215),
    ),
  ],
);

LatLng _forestTreePosition(int index) {
  // Cluster centres create groves and clearings instead of plantation rows.
  const centres = [
    (0.0005, 0.0030),
    (0.0008, 0.0105),
    (0.0024, 0.0060),
    (0.0028, 0.0150),
    (0.0044, 0.0020),
    (0.0048, 0.0115),
    (0.0056, 0.0170),
  ];
  var value = index * 1103515245 + 12345;
  value = (value ^ (value >> 16)) & 0x7fffffff;
  final centre = centres[(value ~/ 97) % centres.length];
  final latJitter = ((value % 10000) / 10000 - .5) * .0018;
  value = (value * 1664525 + 1013904223) & 0x7fffffff;
  final lonJitter = ((value % 10000) / 10000 - .5) * .0024;
  return LatLng(
    46.0687 + centre.$1 + latJitter,
    11.1132 + centre.$2 + lonJitter,
  );
}
