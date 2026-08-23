import 'route_chain_validator.dart';
import 'route_eligibility_gate.dart';
import 'route_topology_graph.dart';

/// Conservative assessment for a complete, preselected route chain.
///
/// The caller owns segment selection. This class has no graph search and does
/// not turn a map line into navigation; it centralizes the conditions that
/// must be met before a future product can even label a route as a proposal.
class RouteProposalAssessment {
  const RouteProposalAssessment({
    required this.eligibility,
    required this.chain,
  });

  final RouteEligibility eligibility;
  final RouteChainValidation chain;
}

abstract final class RouteProposalAssessor {
  static RouteProposalAssessment assess({
    required Iterable<RouteTopologySegment> segments,
    required bool dataIsFresh,
    required bool hasManualRouteReview,
  }) {
    final selectedSegments = segments.toList(growable: false);
    final chain = RouteChainValidator.validate(selectedSegments);
    final sectionEligibility = <RouteEligibility>[];
    for (final segment in selectedSegments) {
      sectionEligibility.add(
        RouteEligibilityGate.evaluate(
          segment.line.metadata,
          evidence: RouteEvidence(
            hasContinuousGeometry: chain.isContinuous,
            dataIsFresh: dataIsFresh,
            hasManualRouteReview: hasManualRouteReview,
          ),
        ),
      );
    }

    if (!chain.isContinuous) {
      return RouteProposalAssessment(
        chain: chain,
        eligibility: RouteEligibility(
          status: RouteProposalStatus.needsVerification,
          reasons: List.unmodifiable(chain.reasons),
        ),
      );
    }

    final blocked = sectionEligibility.where(
      (item) => item.status == RouteProposalStatus.doNotOffer,
    );
    if (blocked.isNotEmpty) {
      return RouteProposalAssessment(
        chain: chain,
        eligibility: RouteEligibility(
          status: RouteProposalStatus.doNotOffer,
          reasons: _reasons(sectionEligibility, RouteProposalStatus.doNotOffer),
        ),
      );
    }

    final uncertain = sectionEligibility.where(
      (item) => item.status == RouteProposalStatus.needsVerification,
    );
    if (uncertain.isNotEmpty) {
      return RouteProposalAssessment(
        chain: chain,
        eligibility: RouteEligibility(
          status: RouteProposalStatus.needsVerification,
          reasons: _reasons(
            sectionEligibility,
            RouteProposalStatus.needsVerification,
          ),
        ),
      );
    }

    return RouteProposalAssessment(
      chain: chain,
      eligibility: const RouteEligibility(
        status: RouteProposalStatus.eligibleForProposal,
        reasons: [],
      ),
    );
  }

  static List<String> _reasons(
    List<RouteEligibility> assessments,
    RouteProposalStatus status,
  ) {
    return List.unmodifiable({
      for (final assessment in assessments)
        if (assessment.status == status) ...assessment.reasons,
    });
  }
}
