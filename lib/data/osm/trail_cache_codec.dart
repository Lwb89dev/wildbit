import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/hiking_trail.dart';
import '../../domain/entities/route_metadata.dart';
import '../../domain/routing/route_eligibility_gate.dart';
import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Versioned, metadata-preserving codec for the local Explore cache.
///
/// We persist the parsed trail summaries rather than the raw Overpass body so
/// stale results remain small, safe to display and independent of API JSON
/// details.
abstract final class TrailCacheCodec {
  static const version = 1;

  static String encode(List<HikingTrail> trails) =>
      jsonEncode({'version': version, 'trails': trails.map(_encode).toList()});

  static List<HikingTrail> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != version) return const [];
    final values = decoded['trails'];
    if (values is! List) return const [];
    return [
      for (final value in values)
        if (value is Map<String, dynamic>) _decode(value),
    ];
  }

  static Map<String, dynamic> _encode(HikingTrail trail) => {
    'id': trail.id,
    'name': trail.name,
    'ref': trail.ref,
    'latitude': trail.position.latitude,
    'longitude': trail.position.longitude,
    'metadata': _encodeMetadata(trail.metadata),
    'route': trail.route == null
        ? null
        : {
            'relationId': trail.route!.relationId,
            'ref': trail.route!.ref,
            'name': trail.route!.name,
            'network': trail.route!.network,
          },
    'lengthKm': trail.lengthKm,
  };

  static HikingTrail _decode(Map<String, dynamic> value) {
    final metadata = _decodeMetadata(
      (value['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final rawRoute = (value['route'] as Map?)?.cast<String, dynamic>();
    return HikingTrail(
      id: value['id'] as String,
      name: value['name'] as String,
      ref: value['ref'] as String?,
      position: LatLng(
        (value['latitude'] as num).toDouble(),
        (value['longitude'] as num).toDouble(),
      ),
      metadata: metadata,
      eligibility: RouteEligibilityGate.evaluate(metadata),
      route: rawRoute == null
          ? null
          : HikingRouteMembership(
              relationId: rawRoute['relationId'] as String,
              ref: rawRoute['ref'] as String?,
              name: rawRoute['name'] as String?,
              network: rawRoute['network'] as String?,
            ),
      lengthKm: (value['lengthKm'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> _encodeMetadata(RouteMetadata metadata) => {
    'osmWayId': metadata.osmWayId,
    'bridgeTag': metadata.bridgeTag,
    'bridgeStructure': metadata.bridgeStructure,
    'surface': metadata.surface,
    'widthMeters': metadata.widthMeters,
    'sacScale': metadata.sacScale,
    'trailVisibility': metadata.trailVisibility,
    'access': metadata.access,
    'footAccess': metadata.footAccess,
    'ref': metadata.ref,
    'highwayTag': metadata.highwayTag,
    'trackType': metadata.trackType,
    'waterwayTag': metadata.waterwayTag,
    'flowDirection': metadata.flowDirection,
    'fordTag': metadata.fordTag,
    'tunnelTag': metadata.tunnelTag,
    'barrierTag': metadata.barrierTag,
    'accessConditional': metadata.accessConditional,
    'footConditional': metadata.footConditional,
    'openingHours': metadata.openingHours,
    'hikingRoutes': [
      for (final route in metadata.hikingRoutes)
        {
          'relationId': route.relationId,
          'ref': route.ref,
          'name': route.name,
          'network': route.network,
        },
    ],
  };

  static RouteMetadata _decodeMetadata(Map<String, dynamic> value) =>
      RouteMetadata(
        osmWayId: value['osmWayId'] as String?,
        bridgeTag: value['bridgeTag'] as String?,
        bridgeStructure: value['bridgeStructure'] as String?,
        surface: value['surface'] as String?,
        widthMeters: (value['widthMeters'] as num?)?.toDouble(),
        sacScale: value['sacScale'] as String?,
        trailVisibility: value['trailVisibility'] as String?,
        access: value['access'] as String?,
        footAccess: value['footAccess'] as String?,
        ref: value['ref'] as String?,
        highwayTag: value['highwayTag'] as String?,
        trackType: value['trackType'] as String?,
        waterwayTag: value['waterwayTag'] as String?,
        flowDirection: value['flowDirection'] as String?,
        fordTag: value['fordTag'] as String?,
        tunnelTag: value['tunnelTag'] as String?,
        barrierTag: value['barrierTag'] as String?,
        accessConditional: value['accessConditional'] as String?,
        footConditional: value['footConditional'] as String?,
        openingHours: value['openingHours'] as String?,
        hikingRoutes: [
          for (final raw in value['hikingRoutes'] as List? ?? const [])
            if (raw is Map)
              HikingRouteMembership(
                relationId: raw['relationId'] as String,
                ref: raw['ref'] as String?,
                name: raw['name'] as String?,
                network: raw['network'] as String?,
              ),
        ],
      );
}
