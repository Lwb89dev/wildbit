import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/entities/poi_metadata.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';

/// A small hand-authored valley used as Phase 1 placeholder geography:
/// a lake fed by a river, a forest slope, a hiking trail and a service
/// road, plus a handful of POIs. Centered roughly on the Italian Alps so
/// default camera coordinates land somewhere plausible for a hiking app.
final LatLng testRegionCenter = LatLng(46.0679, 11.1211);

final MapFeatureCollection testRegionFeatures = MapFeatureCollection(
  areas: [
    // Forest slope, north side of the valley.
    AreaFeature(
      kind: MapFeatureKind.forest,
      ring: [
        LatLng(46.0730, 11.1120),
        LatLng(46.0745, 11.1230),
        LatLng(46.0725, 11.1320),
        LatLng(46.0690, 11.1300),
        LatLng(46.0685, 11.1180),
        LatLng(46.0705, 11.1130),
      ],
    ),
    // Meadow, valley floor.
    AreaFeature(
      kind: MapFeatureKind.meadow,
      ring: [
        LatLng(46.0685, 11.1180),
        LatLng(46.0690, 11.1300),
        LatLng(46.0660, 11.1330),
        LatLng(46.0630, 11.1260),
        LatLng(46.0640, 11.1160),
      ],
    ),
    // Mountain rock, south ridge.
    AreaFeature(
      kind: MapFeatureKind.mountainRock,
      ring: [
        LatLng(46.0630, 11.1260),
        LatLng(46.0600, 11.1330),
        LatLng(46.0560, 11.1290),
        LatLng(46.0570, 11.1180),
        LatLng(46.0610, 11.1150),
        LatLng(46.0640, 11.1160),
      ],
    ),
    // Snow cap on the summit.
    AreaFeature(
      kind: MapFeatureKind.snow,
      ring: [
        LatLng(46.0610, 11.1230),
        LatLng(46.0600, 11.1270),
        LatLng(46.0580, 11.1250),
        LatLng(46.0590, 11.1210),
      ],
    ),
    // Lake.
    AreaFeature(
      kind: MapFeatureKind.water,
      ring: [
        LatLng(46.0665, 11.1210),
        LatLng(46.0670, 11.1250),
        LatLng(46.0655, 11.1270),
        LatLng(46.0640, 11.1250),
        LatLng(46.0645, 11.1215),
      ],
    ),
  ],
  lines: [
    // Hiking trail: forest → lakeshore → summit ridge.
    LineFeature(
      kind: MapFeatureKind.trail,
      name: 'Sentiero del Lago Alto',
      metadata: RouteMetadata(
        ref: '105',
        sacScale: 'mountain_hiking',
        trailVisibility: 'good',
        access: 'yes',
        hikingRoutes: [
          HikingRouteMembership(
            relationId: 'mock-e5',
            ref: 'E5',
            name: 'Sentiero Europeo E5',
            network: 'iwn',
          ),
        ],
      ),
      points: [
        LatLng(46.0740, 11.1150),
        LatLng(46.0700, 11.1190),
        LatLng(46.0672, 11.1215),
        LatLng(46.0655, 11.1270),
        LatLng(46.0620, 11.1290),
        LatLng(46.0595, 11.1245),
      ],
    ),
    LineFeature(
      kind: MapFeatureKind.trail,
      name: 'Tratto non percorribile',
      metadata: RouteMetadata(
        osmWayId: 'mock-restricted',
        ref: 'X1',
        sacScale: 'demanding_mountain_hiking',
        trailVisibility: 'horrible',
        access: 'private',
      ),
      points: [
        LatLng(46.0715, 11.1260),
        LatLng(46.0695, 11.1280),
        LatLng(46.0678, 11.1300),
      ],
    ),
    // Service road along the valley floor.
    LineFeature(
      kind: MapFeatureKind.road,
      name: 'Strada Forestale',
      points: [
        LatLng(46.0645, 11.1160),
        LatLng(46.0655, 11.1220),
        LatLng(46.0645, 11.1280),
        LatLng(46.0625, 11.1310),
      ],
    ),
  ],
  pois: [
    Poi(
      id: 'rifugio-1',
      name: 'Rifugio Alto Lago',
      type: PoiType.shelter,
      position: LatLng(46.0662, 11.1233),
      metadata: PoiMetadata(
        elevationMeters: 1880,
        access: 'yes',
        operatorName: 'CAI - sezione locale',
        openingHours: 'Jun-Sep 08:00-20:00',
      ),
    ),
    Poi(
      id: 'belvedere-1',
      name: 'Punto Panoramico',
      type: PoiType.viewpoint,
      position: LatLng(46.0618, 11.1288),
    ),
    Poi(
      id: 'cartello-1',
      name: 'Bivio del Lago',
      type: PoiType.guidepost,
      position: LatLng(46.0669, 11.1218),
    ),
    Poi(
      id: 'parcheggio-1',
      name: 'Parcheggio Valle',
      type: PoiType.parking,
      position: LatLng(46.0642, 11.1158),
    ),
    Poi(
      id: 'fonte-1',
      name: 'Fonte d\'acqua',
      type: PoiType.waterSource,
      position: LatLng(46.0700, 11.1195),
      metadata: PoiMetadata(drinkingWater: true),
    ),
    Poi(
      id: 'campeggio-1',
      name: 'Area Campeggio',
      type: PoiType.campsite,
      position: LatLng(46.0670, 11.1180),
    ),
  ],
);
