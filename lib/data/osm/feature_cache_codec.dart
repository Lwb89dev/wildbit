import 'dart:convert';

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

/// (De)serializes [MapFeatureCollection] for on-disk caching. This is a data
/// layer concern only — the domain entities themselves stay JSON-agnostic.
abstract final class FeatureCacheCodec {
  // Version 12 preserves surface and obstacle tags used by route artwork.
  static const currentFormatVersion = 16;

  static String encode(MapFeatureCollection features) {
    return jsonEncode({
      'formatVersion': currentFormatVersion,
      'areas': [
        for (final a in features.areas)
          {
            'kind': a.kind.name,
            'ring': _encodePoints(a.ring),
            'holes': [for (final hole in a.holes) _encodePoints(hole)],
            'sourceId': a.sourceId,
          },
      ],
      'lines': [
        for (final l in features.lines)
          {
            'kind': l.kind.name,
            'name': l.name,
            'points': _encodePoints(l.points),
            'nodeIds': l.nodeIds,
            'metadata': {
              'osmWayId': l.metadata.osmWayId,
              'bridgeTag': l.metadata.bridgeTag,
              'bridgeStructure': l.metadata.bridgeStructure,
              'surface': l.metadata.surface,
              'widthMeters': l.metadata.widthMeters,
              'sacScale': l.metadata.sacScale,
              'trailVisibility': l.metadata.trailVisibility,
              'access': l.metadata.access,
              'footAccess': l.metadata.footAccess,
              'ref': l.metadata.ref,
              'hikingRoutes': [
                for (final route in l.metadata.hikingRoutes)
                  {
                    'relationId': route.relationId,
                    'ref': route.ref,
                    'name': route.name,
                    'network': route.network,
                  },
              ],
              'highwayTag': l.metadata.highwayTag,
              'trackType': l.metadata.trackType,
              'waterwayTag': l.metadata.waterwayTag,
              'flowDirection': l.metadata.flowDirection,
              'fordTag': l.metadata.fordTag,
              'tunnelTag': l.metadata.tunnelTag,
              'barrierTag': l.metadata.barrierTag,
              'accessConditional': l.metadata.accessConditional,
              'footConditional': l.metadata.footConditional,
              'openingHours': l.metadata.openingHours,
            },
          },
      ],
      'pois': [
        for (final p in features.pois)
          {
            'id': p.id,
            'name': p.name,
            'type': p.type.name,
            'lat': p.position.latitude,
            'lng': p.position.longitude,
            'metadata': {
              'elevationMeters': p.metadata.elevationMeters,
              'access': p.metadata.access,
              'drinkingWater': p.metadata.drinkingWater,
              'operatorName': p.metadata.operatorName,
              'openingHours': p.metadata.openingHours,
              'shelterType': p.metadata.shelterType,
            },
          },
      ],
    });
  }

  static MapFeatureCollection decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return MapFeatureCollection(
      areas: [
        for (final a in (map['areas'] as List))
          AreaFeature(
            kind: MapFeatureKind.values.byName(a['kind'] as String),
            ring: _decodePoints(a['ring'] as List),
            holes: [
              for (final hole in a['holes'] as List? ?? const [])
                _decodePoints(hole as List),
            ],
            sourceId: a['sourceId'] as String?,
          ),
      ],
      lines: [
        for (final l in (map['lines'] as List))
          LineFeature(
            kind: MapFeatureKind.values.byName(l['kind'] as String),
            name: l['name'] as String?,
            points: _decodePoints(l['points'] as List),
            nodeIds: (l['nodeIds'] as List? ?? const [])
                .map((nodeId) => nodeId.toString())
                .toList(growable: false),
            metadata: _decodeRouteMetadata(l['metadata']),
          ),
      ],
      pois: [
        for (final p in (map['pois'] as List))
          Poi(
            id: p['id'] as String,
            name: p['name'] as String,
            type: PoiType.values.byName(p['type'] as String),
            position: LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
            metadata: _decodePoiMetadata(p['metadata']),
          ),
      ],
    );
  }

  /// Old cached cells omitted ordered way-node references. They are still
  /// readable for an offline fallback, but must not be considered fresh for
  /// global coastline assembly.
  static bool isCurrentFormat(String json) {
    try {
      final map = jsonDecode(json);
      return map is Map && map['formatVersion'] == currentFormatVersion;
    } catch (_) {
      return false;
    }
  }

  static List<List<double>> _encodePoints(List<LatLng> points) {
    return [
      for (final p in points) [p.latitude, p.longitude],
    ];
  }

  static List<LatLng> _decodePoints(List raw) {
    return [
      for (final p in raw)
        LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
  }

  static RouteMetadata _decodeRouteMetadata(Object? raw) {
    if (raw is! Map) return const RouteMetadata();
    return RouteMetadata(
      osmWayId: raw['osmWayId'] as String?,
      bridgeTag: raw['bridgeTag'] as String?,
      bridgeStructure: raw['bridgeStructure'] as String?,
      surface: raw['surface'] as String?,
      widthMeters: (raw['widthMeters'] as num?)?.toDouble(),
      sacScale: raw['sacScale'] as String?,
      trailVisibility: raw['trailVisibility'] as String?,
      access: raw['access'] as String?,
      footAccess: raw['footAccess'] as String?,
      ref: raw['ref'] as String?,
      hikingRoutes: [
        for (final route in raw['hikingRoutes'] as List? ?? const [])
          if (route is Map && route['relationId'] != null)
            HikingRouteMembership(
              relationId: route['relationId'].toString(),
              ref: route['ref'] as String?,
              name: route['name'] as String?,
              network: route['network'] as String?,
            ),
      ],
      highwayTag: raw['highwayTag'] as String?,
      trackType: raw['trackType'] as String?,
      waterwayTag: raw['waterwayTag'] as String?,
      flowDirection: raw['flowDirection'] as String?,
      fordTag: raw['fordTag'] as String?,
      tunnelTag: raw['tunnelTag'] as String?,
      barrierTag: raw['barrierTag'] as String?,
      accessConditional: raw['accessConditional'] as String?,
      footConditional: raw['footConditional'] as String?,
      openingHours: raw['openingHours'] as String?,
    );
  }

  static PoiMetadata _decodePoiMetadata(Object? raw) {
    if (raw is! Map) return const PoiMetadata();
    return PoiMetadata(
      elevationMeters: (raw['elevationMeters'] as num?)?.toDouble(),
      access: raw['access'] as String?,
      drinkingWater: raw['drinkingWater'] as bool?,
      operatorName: raw['operatorName'] as String?,
      openingHours: raw['openingHours'] as String?,
      shelterType: raw['shelterType'] as String?,
    );
  }
}
