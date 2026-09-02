import 'package:latlong2/latlong.dart';

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/entities/poi_metadata.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/enums/poi_type.dart';
import '../../map_rendering/composition/osm_multipolygon_composer.dart';

/// Turns a raw Overpass API JSON response into WildBit's own map entities.
/// This is the one place that knows about OSM tags — everything downstream
/// (caching, rendering, presentation) only ever sees [MapFeatureCollection].
abstract final class OverpassParser {
  static MapFeatureCollection parse(Map<String, dynamic> json) {
    final areas = <AreaFeature>[];
    final lines = <LineFeature>[];
    final pois = <Poi>[];
    final elements = json['elements'] as List? ?? const [];
    final multipolygonWayIds = _multipolygonMemberWayIds(elements);
    final hikingRoutesByWay = _hikingRoutesByWay(elements);

    for (final element in elements) {
      final map = element as Map<String, dynamic>;
      final tags = (map['tags'] as Map?)?.cast<String, String>() ?? const {};
      switch (map['type']) {
        case 'way':
          _parseWay(
            map,
            tags,
            areas,
            lines,
            pois,
            hikingRoutesByWay,
            skipAreaWayIds: multipolygonWayIds,
          );
        case 'node':
          _parseNode(map, tags, pois);
        case 'relation':
          _parseRelation(map, tags, areas, pois);
      }
    }

    return MapFeatureCollection(areas: areas, lines: lines, pois: pois);
  }

  static void _parseWay(
    Map<String, dynamic> way,
    Map<String, String> tags,
    List<AreaFeature> areas,
    List<LineFeature> lines,
    List<Poi> pois,
    Map<String, List<HikingRouteMembership>> hikingRoutesByWay, {
    Set<String> skipAreaWayIds = const {},
  }) {
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

    final poiType = _poiTypeForTags(tags);
    if (poiType != null) {
      _addPoi(
        pois,
        osmType: 'way',
        osmId: way['id'],
        tags: tags,
        type: poiType,
        position: _representativePoint(geometry),
      );
    }

    final areaKind = _areaKindForTags(tags);
    if (areaKind != null && !skipAreaWayIds.contains(way['id']?.toString())) {
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
            hikingRoutes: hikingRoutesByWay[way['id']?.toString()] ?? const [],
          ),
          nodeIds: nodeIds,
        ),
      );
    }
  }

  static Map<String, List<HikingRouteMembership>> _hikingRoutesByWay(
    List elements,
  ) {
    final result = <String, List<HikingRouteMembership>>{};
    for (final rawElement in elements) {
      if (rawElement is! Map || rawElement['type'] != 'relation') continue;
      final rawTags = rawElement['tags'];
      if (rawTags is! Map) continue;
      final tags = rawTags.cast<String, String>();
      if (tags['type'] != 'route' ||
          !const {'hiking', 'foot'}.contains(tags['route'])) {
        continue;
      }
      final relationId = rawElement['id']?.toString();
      if (relationId == null) continue;
      final membership = HikingRouteMembership(
        relationId: relationId,
        ref: _nonEmpty(tags['ref']),
        name: _nonEmpty(tags['name']),
        network: _nonEmpty(tags['network']),
      );
      for (final rawMember in rawElement['members'] as List? ?? const []) {
        if (rawMember is! Map || rawMember['type'] != 'way') continue;
        final wayId = rawMember['ref']?.toString();
        if (wayId == null) continue;
        (result[wayId] ??= []).add(membership);
      }
    }
    for (final memberships in result.values) {
      memberships.sort((a, b) {
        final priority = a.displayPriority.compareTo(b.displayPriority);
        return priority != 0 ? priority : a.relationId.compareTo(b.relationId);
      });
    }
    return result;
  }

  static String? _nonEmpty(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Set<String> _multipolygonMemberWayIds(List elements) {
    final ids = <String>{};
    for (final raw in elements) {
      if (raw is! Map || raw['type'] != 'relation') continue;
      final tags = (raw['tags'] as Map?)?.cast<String, String>() ?? const {};
      if (tags['type'] != 'multipolygon') continue;
      final relation = raw.cast<String, dynamic>();
      final composition = OsmMultipolygonComposer.compose(
        _multipolygonMembers(relation),
      );
      if (!composition.isComplete) continue;
      for (final member in raw['members'] as List? ?? const []) {
        if (member is Map && member['type'] == 'way') {
          final id = member['ref']?.toString();
          if (id != null) ids.add(id);
        }
      }
    }
    return ids;
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

    _addPoi(
      pois,
      osmType: 'node',
      osmId: node['id'],
      tags: tags,
      type: type,
      position: LatLng(lat.toDouble(), lon.toDouble()),
    );
  }

  static void _parseRelation(
    Map<String, dynamic> relation,
    Map<String, String> tags,
    List<AreaFeature> areas,
    List<Poi> pois,
  ) {
    if (tags['type'] == 'multipolygon') {
      _parseMultipolygonRelation(relation, tags, areas);
    }
    final type = _poiTypeForTags(tags);
    if (type == null) return;
    final center = relation['center'] as Map?;
    final centerLat = center?['lat'] as num?;
    final centerLon = center?['lon'] as num?;
    LatLng? position;
    if (centerLat != null && centerLon != null) {
      position = LatLng(centerLat.toDouble(), centerLon.toDouble());
    } else {
      final geometry = <LatLng>[];
      for (final rawMember in relation['members'] as List? ?? const []) {
        if (rawMember is! Map) continue;
        for (final rawPoint in rawMember['geometry'] as List? ?? const []) {
          if (rawPoint is! Map) continue;
          final lat = rawPoint['lat'] as num?;
          final lon = rawPoint['lon'] as num?;
          if (lat != null && lon != null) {
            geometry.add(LatLng(lat.toDouble(), lon.toDouble()));
          }
        }
      }
      if (geometry.isNotEmpty) position = _representativePoint(geometry);
    }
    if (position == null) return;
    _addPoi(
      pois,
      osmType: 'relation',
      osmId: relation['id'],
      tags: tags,
      type: type,
      position: position,
    );
  }

  static void _parseMultipolygonRelation(
    Map<String, dynamic> relation,
    Map<String, String> tags,
    List<AreaFeature> areas,
  ) {
    final kind = _areaKindForTags(tags);
    final relationId = relation['id']?.toString();
    if (kind == null || relationId == null) return;
    final composition = OsmMultipolygonComposer.compose(
      _multipolygonMembers(relation),
    );
    // An incomplete relation is not safe to fill: member ways remain
    // available as standalone geometry when they carry their own tags.
    if (!composition.isComplete) return;
    for (var index = 0; index < composition.polygons.length; index++) {
      final polygon = composition.polygons[index];
      areas.add(
        AreaFeature(
          kind: kind,
          ring: polygon.outer,
          holes: polygon.holes,
          sourceId: 'relation-$relationId-$index',
        ),
      );
    }
  }

  static List<MultipolygonMember> _multipolygonMembers(
    Map<String, dynamic> relation,
  ) {
    final members = <MultipolygonMember>[];
    for (final rawMember in relation['members'] as List? ?? const []) {
      if (rawMember is! Map || rawMember['type'] != 'way') continue;
      final geometry = <LatLng>[];
      for (final rawPoint in rawMember['geometry'] as List? ?? const []) {
        if (rawPoint is! Map) continue;
        final latitude = rawPoint['lat'];
        final longitude = rawPoint['lon'];
        if (latitude is num && longitude is num) {
          geometry.add(LatLng(latitude.toDouble(), longitude.toDouble()));
        }
      }
      // Preserve unknown roles and missing geometry as explicit invalid input.
      // Silently discarding them could make an incomplete relation appear
      // complete and suppress the safe standalone-way fallback.
      members.add(
        MultipolygonMember(
          role: rawMember['role']?.toString() ?? '',
          points: List.unmodifiable(geometry),
        ),
      );
    }
    return members;
  }

  static void _addPoi(
    List<Poi> pois, {
    required String osmType,
    required Object? osmId,
    required Map<String, String> tags,
    required PoiType type,
    required LatLng position,
  }) {
    if (osmId == null) return;
    pois.add(
      Poi(
        id: 'osm-$osmType-$osmId',
        name: tags['name'] ?? _defaultNameFor(type),
        type: type,
        position: position,
        metadata: PoiMetadata.fromOsmTags(tags, type: type),
      ),
    );
  }

  static LatLng _representativePoint(List<LatLng> geometry) {
    if (geometry.length < 3) {
      final latitude =
          geometry.fold<double>(0, (sum, point) => sum + point.latitude) /
          geometry.length;
      final longitude =
          geometry.fold<double>(0, (sum, point) => sum + point.longitude) /
          geometry.length;
      return LatLng(latitude, longitude);
    }

    // Shoelace centroid for ordinary closed OSM ways. It provides a stable
    // point near the visual centre without relying on screen coordinates.
    var twiceArea = 0.0;
    var longitudeMoment = 0.0;
    var latitudeMoment = 0.0;
    for (var index = 0; index < geometry.length; index++) {
      final current = geometry[index];
      final next = geometry[(index + 1) % geometry.length];
      final cross =
          current.longitude * next.latitude - next.longitude * current.latitude;
      twiceArea += cross;
      longitudeMoment += (current.longitude + next.longitude) * cross;
      latitudeMoment += (current.latitude + next.latitude) * cross;
    }
    if (twiceArea.abs() > 1e-12) {
      return LatLng(
        latitudeMoment / (3 * twiceArea),
        longitudeMoment / (3 * twiceArea),
      );
    }
    final latitude =
        geometry.fold<double>(0, (sum, point) => sum + point.latitude) /
        geometry.length;
    final longitude =
        geometry.fold<double>(0, (sum, point) => sum + point.longitude) /
        geometry.length;
    return LatLng(latitude, longitude);
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

  static const _trailHighways = {
    'path',
    'footway',
    'track',
    'steps',
    'bridleway',
    'via_ferrata',
  };
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
    if (tags['ford'] == 'yes' || tags['ford'] == 'true') {
      return PoiType.ford;
    }
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
    PoiType.ford => 'Guado',
  };
}
