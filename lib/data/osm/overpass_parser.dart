import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/entities/poi_metadata.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';

/// Turns a raw Overpass API JSON response into WildBit's own map entities.
/// This is the one place that knows about OSM tags — everything downstream
/// (caching, rendering, presentation) only ever sees [MapFeatureCollection].
abstract final class OverpassParser {
  static MapFeatureCollection parse(Map<String, dynamic> json) {
    final areas = <AreaFeature>[];
    final lines = <LineFeature>[];
    final pois = <Poi>[];

    for (final element in (json['elements'] as List? ?? const [])) {
      final map = element as Map<String, dynamic>;
      final tags = (map['tags'] as Map?)?.cast<String, String>() ?? const {};
      switch (map['type']) {
        case 'way':
          _parseWay(map, tags, areas, lines);
        case 'node':
          _parseNode(map, tags, pois);
      }
    }

    return MapFeatureCollection(areas: areas, lines: lines, pois: pois);
  }

  static void _parseWay(
    Map<String, dynamic> way,
    Map<String, String> tags,
    List<AreaFeature> areas,
    List<LineFeature> lines,
  ) {
    final geometry = (way['geometry'] as List?)
        ?.map(
          (p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lon'] as num).toDouble(),
          ),
        )
        .toList();
    final nodeIds =
        (way['nodes'] as List?)
            ?.map((nodeId) => nodeId.toString())
            .toList(growable: false) ??
        const <String>[];
    if (geometry == null || geometry.length < 2) return;

    final areaKind = _areaKindForTags(tags);
    if (areaKind != null) {
      areas.add(
        AreaFeature(
          kind: areaKind,
          ring: geometry,
          sourceId: way['id']?.toString(),
        ),
      );
      return;
    }

    final lineKind = _lineKindForTags(tags);
    if (lineKind != null) {
      lines.add(
        LineFeature(
          kind: lineKind,
          points: geometry,
          name: tags['name'],
          metadata: RouteMetadata.fromOsmTags(
            tags,
            wayId: way['id']?.toString(),
          ),
          nodeIds: nodeIds,
        ),
      );
    }
  }

  static void _parseNode(
    Map<String, dynamic> node,
    Map<String, String> tags,
    List<Poi> pois,
  ) {
    final lat = node['lat'] as num?;
    final lon = node['lon'] as num?;
    if (lat == null || lon == null) return;

    final type = _poiTypeForTags(tags);
    if (type == null) return;

    pois.add(
      Poi(
        id: 'osm-node-${node['id']}',
        name: tags['name'] ?? _defaultNameFor(type),
        type: type,
        position: LatLng(lat.toDouble(), lon.toDouble()),
        metadata: PoiMetadata.fromOsmTags(tags, type: type),
      ),
    );
  }

  static MapFeatureKind? _areaKindForTags(Map<String, String> tags) {
    if (tags.containsKey('building')) return MapFeatureKind.building;
    if (tags['natural'] == 'wood' || tags['landuse'] == 'forest') {
      return MapFeatureKind.forest;
    }
    if (tags['landuse'] == 'meadow' || tags['natural'] == 'grassland') {
      return MapFeatureKind.meadow;
    }
    if (tags['leisure'] == 'park') return MapFeatureKind.park;
    if (tags['natural'] == 'water' || tags['waterway'] == 'riverbank') {
      return MapFeatureKind.water;
    }
    if (tags['natural'] == 'bare_rock' || tags['natural'] == 'scree') {
      return MapFeatureKind.mountainRock;
    }
    if (tags['natural'] == 'glacier') return MapFeatureKind.snow;
    return null;
  }

  static const _trailHighways = {'path', 'footway', 'track', 'steps'};
  static const _roadHighways = {
    'residential',
    'service',
    'unclassified',
    'tertiary',
    'secondary',
    'primary',
  };

  static MapFeatureKind? _lineKindForTags(Map<String, String> tags) {
    if (tags['natural'] == 'coastline') return MapFeatureKind.coastline;
    if (const {
      'river',
      'stream',
      'canal',
      'ditch',
    }.contains(tags['waterway'])) {
      return MapFeatureKind.waterway;
    }
    final highway = tags['highway'];
    if (highway == null) return null;
    if (_trailHighways.contains(highway)) return MapFeatureKind.trail;
    if (_roadHighways.contains(highway)) return MapFeatureKind.road;
    return null;
  }

  static PoiType? _poiTypeForTags(Map<String, String> tags) {
    if (tags['tourism'] == 'viewpoint') return PoiType.viewpoint;
    if (tags['tourism'] == 'alpine_hut' ||
        tags['tourism'] == 'wilderness_hut' ||
        tags['amenity'] == 'shelter') {
      return PoiType.shelter;
    }
    if (tags['tourism'] == 'information' &&
        tags['information'] == 'guidepost') {
      return PoiType.guidepost;
    }
    if (tags['tourism'] == 'camp_site') return PoiType.campsite;
    if (tags['amenity'] == 'parking') return PoiType.parking;
    if (tags['natural'] == 'spring' || tags['amenity'] == 'drinking_water') {
      return PoiType.waterSource;
    }
    if (tags['natural'] == 'peak') return PoiType.summit;
    if (tags['natural'] == 'tree') return PoiType.tree;
    return null;
  }

  static String _defaultNameFor(PoiType type) => switch (type) {
    PoiType.shelter => 'Rifugio',
    PoiType.campsite => 'Campeggio',
    PoiType.viewpoint => 'Punto panoramico',
    PoiType.guidepost => 'Cartello escursionistico',
    PoiType.parking => 'Parcheggio',
    PoiType.waterSource => 'Fonte d\'acqua',
    PoiType.summit => 'Vetta',
    PoiType.tree => 'Albero',
  };
}
