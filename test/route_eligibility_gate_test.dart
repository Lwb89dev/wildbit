import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/routing/route_eligibility_gate.dart';

void main() {
  test('never offers a segment with restricted pedestrian access', () {
    final result = RouteEligibilityGate.evaluate(
      const RouteMetadata(access: 'private', footAccess: 'yes'),
      evidence: const RouteEvidence(
        hasContinuousGeometry: true,
        dataIsFresh: true,
        hasManualRouteReview: true,
      ),
    );
    expect(result.status, RouteProposalStatus.doNotOffer);
    expect(result.mayBeProposed, isFalse);
  });

  test('treats an explicitly private foot tag as restricted', () {
    final result = RouteEligibilityGate.evaluate(
      const RouteMetadata(access: 'yes', footAccess: 'private'),
      evidence: const RouteEvidence(
        hasContinuousGeometry: true,
        dataIsFresh: true,
        hasManualRouteReview: true,
      ),
    );

    expect(result.status, RouteProposalStatus.doNotOffer);
  });

  test('unknown or incomplete OSM data requires verification', () {
    final result = RouteEligibilityGate.evaluate(const RouteMetadata());
    expect(result.status, RouteProposalStatus.needsVerification);
    expect(result.mayBeProposed, isFalse);
    expect(result.reasons, contains('continuità non verificata'));
  });

  test('conditional access never becomes an automatically eligible route', () {
    final result = RouteEligibilityGate.evaluate(
      const RouteMetadata(
        access: 'yes',
        footAccess: 'yes',
        sacScale: 'hiking',
        trailVisibility: 'good',
        openingHours: 'May-Oct',
      ),
      evidence: const RouteEvidence(
        hasContinuousGeometry: true,
        dataIsFresh: true,
        hasManualRouteReview: true,
      ),
    );

    expect(result.status, RouteProposalStatus.needsVerification);
    expect(result.reasons, contains('accesso condizionale da verificare'));
  });

  test('only complete reviewed evidence can be proposed', () {
    final result = RouteEligibilityGate.evaluate(
      const RouteMetadata(
        access: 'permissive',
        footAccess: 'yes',
        sacScale: 'hiking',
        trailVisibility: 'good',
      ),
      evidence: const RouteEvidence(
        hasContinuousGeometry: true,
        dataIsFresh: true,
        hasManualRouteReview: true,
      ),
    );
    expect(result.status, RouteProposalStatus.eligibleForProposal);
  });
}
