import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/trail_classification.dart';

class RouteLabelContent {
  const RouteLabelContent({
    required this.text,
    required this.priority,
    required this.hasReference,
    this.membership,
  });

  final String text;
  final int priority;
  final bool hasReference;
  final HikingRouteMembership? membership;

  static RouteLabelContent? forLine(LineFeature line, double zoom) {
    final membership = line.metadata.hikingRoutes.firstOrNull;
    final relationRef = _value(membership?.ref);
    final relationName = _value(membership?.name);
    final ref = relationRef ?? _value(line.metadata.ref);
    final name = relationName ?? _value(line.name);
    final classification = TrailClassification.fromMetadata(line.metadata);
    final difficulty = classification.difficulty.label;
    final restricted = classification.access == TrailAccessStatus.restricted;

    if (zoom < 12 ||
        (!restricted && ref == null && difficulty == null && name == null) ||
        (!restricted && ref == null && zoom < 13) ||
        (!restricted && ref == null && difficulty == null && zoom < 13.5)) {
      return null;
    }

    final visibleDifficulty = zoom >= 13 ? difficulty : null;
    final visibleName =
        zoom >= 15 || (ref == null && difficulty == null && zoom >= 13.5)
        ? name
        : null;
    final parts = <String>[
      if (restricted) 'VIETATO',
      ?ref,
      ?visibleDifficulty,
      ?visibleName,
    ];
    if (parts.isEmpty) return null;
    return RouteLabelContent(
      text: parts.join(' · '),
      priority: restricted
          ? -1
          : membership?.displayPriority ?? (ref != null ? 5 : 6),
      hasReference: ref != null,
      membership: membership,
    );
  }

  static String? _value(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
