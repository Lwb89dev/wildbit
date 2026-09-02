import 'package:latlong2/latlong.dart';

import '../../data/osm/overpass_parser.dart';
import '../../domain/entities/map_feature_collection.dart';

/// Deterministic OSM/Overpass-shaped response used by the renderer harness.
///
/// This is deliberately raw OSM-shaped input rather than a hand assembled
/// [MapFeatureCollection]. It exercises the same parser, multipolygon
/// composition and tag classification used after an Overpass download, while
/// remaining entirely local and repeatable. It is a visual/regression fixture,
/// never a source of navigation data.
final MapFeatureCollection osmReplayFeatures = OverpassParser.parse(
  osmReplayResponse,
);

/// A compact but topology-rich Overpass response: a lake with an island hole,
/// woodland, meadow, rock, a stream, two paths, a bridge and mapped objects.
final Map<String, dynamic> osmReplayResponse = {
  'version': 0.6,
  'generator': 'WildBit deterministic renderer replay',
  'elements': [
    {
      'type': 'way',
      'id': 1001,
      'tags': {'landuse': 'forest', 'name': 'Bosco di prova'},
      'geometry': _ring(const [
        LatLng(46.0748, 11.1112),
        LatLng(46.0754, 11.1238),
        LatLng(46.0710, 11.1308),
        LatLng(46.0678, 11.1242),
        LatLng(46.0698, 11.1142),
      ]),
    },
    {
      'type': 'way',
      'id': 1002,
      'tags': {'landuse': 'meadow', 'name': 'Piana del torrente'},
      'geometry': _ring(const [
        LatLng(46.0688, 11.1150),
        LatLng(46.0693, 11.1308),
        LatLng(46.0634, 11.1330),
        LatLng(46.0618, 11.1215),
        LatLng(46.0650, 11.1138),
      ]),
    },
    {
      'type': 'way',
      'id': 1003,
      'tags': {'natural': 'bare_rock', 'name': 'Costa rocciosa'},
      'geometry': _ring(const [
        LatLng(46.0632, 11.1302),
        LatLng(46.0612, 11.1340),
        LatLng(46.0574, 11.1312),
        LatLng(46.0595, 11.1262),
      ]),
    },
    {
      'type': 'relation',
      'id': 2001,
      'tags': {
        'type': 'multipolygon',
        'natural': 'water',
        'name': 'Lago della Valle',
      },
      'members': [
        _member(2101, 'outer', const [
          LatLng(46.0674, 11.1204),
          LatLng(46.0681, 11.1248),
          LatLng(46.0666, 11.1284),
        ]),
        _member(2102, 'outer', const [
          LatLng(46.0666, 11.1284),
          LatLng(46.0630, 11.1272),
          LatLng(46.0622, 11.1230),
        ]),
        _member(2103, 'outer', const [
          LatLng(46.0622, 11.1230),
          LatLng(46.0640, 11.1206),
          LatLng(46.0674, 11.1204),
        ]),
        _member(2110, 'inner', const [
          LatLng(46.0658, 11.1238),
          LatLng(46.0661, 11.1247),
          LatLng(46.0656, 11.1253),
          LatLng(46.0651, 11.1246),
          LatLng(46.0658, 11.1238),
        ]),
      ],
    },
    {
      'type': 'way',
      'id': 3001,
      'tags': {'waterway': 'stream', 'name': 'Rio della Valle'},
      'geometry': _points(const [
        LatLng(46.0754, 11.1272),
        LatLng(46.0726, 11.1264),
        LatLng(46.0695, 11.1257),
        LatLng(46.0668, 11.1248),
      ]),
    },
    {
      'type': 'way',
      'id': 3002,
      'nodes': [4101, 4102, 4103, 4104],
      'tags': {
        'highway': 'path',
        'name': 'Sentiero del Lago',
        'ref': 'AV-17',
        'sac_scale': 'mountain_hiking',
        'trail_visibility': 'good',
      },
      'geometry': _points(const [
        LatLng(46.0741, 11.1152),
        LatLng(46.0708, 11.1184),
        LatLng(46.0677, 11.1223),
        LatLng(46.0640, 11.1268),
      ]),
    },
    {
      'type': 'way',
      'id': 3003,
      'nodes': [4201, 4202, 4203],
      'tags': {
        'highway': 'track',
        'name': 'Variante del Bosco',
        'surface': 'ground',
        'bridge': 'yes',
        'bridge:structure': 'wood',
      },
      'geometry': _points(const [
        LatLng(46.0681, 11.1241),
        LatLng(46.0675, 11.1258),
        LatLng(46.0669, 11.1274),
      ]),
    },
    {
      'type': 'way',
      'id': 3004,
      'nodes': [4301, 4302, 4303],
      'tags': {'highway': 'service', 'name': 'Strada forestale'},
      'geometry': _points(const [
        LatLng(46.0616, 11.1150),
        LatLng(46.0639, 11.1196),
        LatLng(46.0648, 11.1230),
      ]),
    },
    {
      'type': 'relation',
      'id': 5001,
      'tags': {
        'type': 'route',
        'route': 'hiking',
        'ref': 'AV-17',
        'name': 'Alta Via locale',
        'network': 'rwn',
      },
      'members': [
        {'type': 'way', 'ref': 3002, 'role': ''},
      ],
    },
    for (var index = 0; index < 92; index++) _treeNode(index),
    {
      'type': 'node',
      'id': 6001,
      'lat': 46.0674,
      'lon': 11.1219,
      'tags': {
        'tourism': 'alpine_hut',
        'name': 'Rifugio della Valle',
        'ele': '1850',
      },
    },
    {
      'type': 'node',
      'id': 6002,
      'lat': 46.0680,
      'lon': 11.1228,
      'tags': {
        'tourism': 'information',
        'information': 'guidepost',
        'name': 'Bivio del Lago',
      },
    },
    {
      'type': 'node',
      'id': 6003,
      'lat': 46.0710,
      'lon': 11.1182,
      'tags': {'natural': 'spring', 'drinking_water': 'yes'},
    },
    {
      'type': 'node',
      'id': 6004,
      'lat': 46.0602,
      'lon': 11.1300,
      'tags': {'natural': 'peak', 'name': 'Cima della Valle', 'ele': '2140'},
    },
  ],
};

Map<String, dynamic> _member(int id, String role, List<LatLng> geometry) => {
  'type': 'way',
  'ref': id,
  'role': role,
  'geometry': _points(geometry),
};

List<Map<String, double>> _ring(List<LatLng> points) =>
    _points([...points, points.first]);

List<Map<String, double>> _points(List<LatLng> points) => [
  for (final point in points) {'lat': point.latitude, 'lon': point.longitude},
];

Map<String, dynamic> _treeNode(int index) {
  // Clusters and clearings exercise the same non-grid distribution expected
  // from actual tagged trees in a woodland, without runtime randomness.
  final cluster = index % 4;
  final row = index ~/ 4;
  return {
    'type': 'node',
    'id': 7000 + index,
    'lat': 46.0700 + cluster * .00082 + (row % 6) * .00021,
    'lon': 11.1135 + row * .00042 + (cluster % 2) * .00017,
    'tags': {'natural': 'tree'},
  };
}
