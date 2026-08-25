import 'package:latlong2/latlong.dart';

import '../routing/route_eligibility_gate.dart';
import 'hiking_route_membership.dart';
import 'route_metadata.dart';

/// A named hiking-capable way returned by OpenStreetMap.
///
/// [route] is set only when this result comes from an OSM hiking *route
/// relation* (`type=route`, `route=hiking`/`foot`) rather than a bare way
/// segment — a curated, named, usually maintained long-distance trail (e.g.
/// a CAI-numbered path, a GR, an E-route) as opposed to an arbitrary path or
/// service road that merely happens to be walkable.
class HikingTrail {
  const HikingTrail({
    required this.id,
    required this.name,
    required this.position,
    this.ref,
    this.metadata = const RouteMetadata(),
    this.eligibility = const RouteEligibility(
      status: RouteProposalStatus.needsVerification,
      reasons: ['continuità non verificata'],
    ),
    this.route,
    this.lengthKm,
  });

  final String id;
  final String name;
  final LatLng position;
  final String? ref;
  final RouteMetadata metadata;
  final RouteEligibility eligibility;

  /// Non-null only for a curated route-relation result.
  final HikingRouteMembership? route;

  /// The route's own total length in kilometres, when OSM has it (either an
  /// explicit `distance` tag on the relation, or summed from member ways).
  /// This is the trail's *extension*, not the distance from the user to it.
  final double? lengthKm;

  bool get isCuratedRoute => route != null;
}
