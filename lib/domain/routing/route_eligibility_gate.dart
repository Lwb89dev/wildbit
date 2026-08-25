import '../entities/route_metadata.dart';
import '../entities/trail_classification.dart';

/// Conservative decision for route *proposals*, never a safety guarantee.
enum RouteProposalStatus { doNotOffer, needsVerification, eligibleForProposal }

class RouteEvidence {
  const RouteEvidence({
    this.hasContinuousGeometry = false,
    this.dataIsFresh = false,
    this.hasManualRouteReview = false,
  });

  final bool hasContinuousGeometry;
  final bool dataIsFresh;
  final bool hasManualRouteReview;
}

class RouteEligibility {
  const RouteEligibility({required this.status, required this.reasons});

  final RouteProposalStatus status;
  final List<String> reasons;

  bool get mayBeProposed => status == RouteProposalStatus.eligibleForProposal;
}

abstract final class RouteEligibilityGate {
  static RouteEligibility evaluate(
    RouteMetadata metadata, {
    RouteEvidence evidence = const RouteEvidence(),
  }) {
    final classification = TrailClassification.fromMetadata(metadata);
    if (classification.access == TrailAccessStatus.restricted) {
      return const RouteEligibility(
        status: RouteProposalStatus.doNotOffer,
        reasons: ['Accesso pedonale non consentito o privato secondo OSM'],
      );
    }

    final missing = <String>[];
    if (metadata.access == null && metadata.footAccess == null) {
      missing.add('accesso pedonale non mappato');
    }
    if (metadata.hasConditionalAccess) {
      missing.add('accesso condizionale da verificare');
    }
    if (metadata.sacScale == null) {
      missing.add('difficoltà non mappata');
    }
    if (metadata.trailVisibility == null) {
      missing.add('visibilità non mappata');
    }
    if (!evidence.hasContinuousGeometry) {
      missing.add('continuità non verificata');
    }
    if (!evidence.dataIsFresh) {
      missing.add('dato non aggiornato/verificato');
    }
    if (!evidence.hasManualRouteReview) {
      missing.add('revisione umana assente');
    }

    if (missing.isNotEmpty) {
      return RouteEligibility(
        status: RouteProposalStatus.needsVerification,
        reasons: missing,
      );
    }
    return const RouteEligibility(
      status: RouteProposalStatus.eligibleForProposal,
      reasons: [],
    );
  }
}
