import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/routing/route_eligibility_gate.dart';
import 'package:wildbit/domain/routing/route_proposal_assessor.dart';
import 'package:wildbit/domain/routing/route_topology_graph.dart';

RouteTopologySegment _safeSegment(String start, String end, String id) {
  const metadata = RouteMetadata(
    access: 'permissive',
    footAccess: 'yes',
    sacScale: 'hiking',
    trailVisibility: 'good',
  );
  return RouteTopologySegment(
    wayId: id,
    startNodeId: start,
    endNodeId: end,
    segmentIndex: 0,
    line: LineFeature(
      kind: MapFeatureKind.trail,
      points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
      nodeIds: [start, end],
      metadata: metadata,
    ),
  );
}

void main() {
  test('requires a contiguous chain before all other positive evidence', () {
    final assessment = RouteProposalAssessor.assess(
      segments: [_safeSegment('1', '2', '1'), _safeSegment('3', '4', '2')],
      dataIsFresh: true,
      hasManualRouteReview: true,
    );

    expect(
      assessment.eligibility.status,
      RouteProposalStatus.needsVerification,
    );
    expect(assessment.eligibility.reasons.single, contains('non connessi'));
  });

  test('still requires human review of an otherwise valid route chain', () {
    final assessment = RouteProposalAssessor.assess(
      segments: [_safeSegment('1', '2', '1'), _safeSegment('2', '3', '2')],
      dataIsFresh: true,
      hasManualRouteReview: false,
    );

    expect(
      assessment.eligibility.status,
      RouteProposalStatus.needsVerification,
    );
    expect(assessment.eligibility.reasons, contains('revisione umana assente'));
  });
}
