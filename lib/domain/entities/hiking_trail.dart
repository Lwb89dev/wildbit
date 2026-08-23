import 'package:latlong2/latlong.dart';

import '../routing/route_eligibility_gate.dart';
import 'route_metadata.dart';

/// A named hiking-capable way returned by OpenStreetMap.
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
  });

  final String id;
  final String name;
  final LatLng position;
  final String? ref;
  final RouteMetadata metadata;
  final RouteEligibility eligibility;
}
