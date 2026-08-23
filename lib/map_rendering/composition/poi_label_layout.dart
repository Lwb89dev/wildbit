import 'dart:ui';

class PoiLabelCandidate {
  const PoiLabelCandidate({
    required this.id,
    required this.markerRect,
    required this.labelSize,
    required this.priority,
  });

  final String id;
  final Rect markerRect;
  final Size labelSize;
  final int priority;
}

class PoiLabelPlacement {
  const PoiLabelPlacement({required this.id, required this.rect});

  final String id;
  final Rect rect;
}

/// Deterministic, screen-space label placement for the interactive map.
/// Markers are always reserved first: when space runs out only the label is
/// omitted, never the geographic object it describes.
abstract final class PoiLabelLayout {
  static List<PoiLabelPlacement> compose({
    required List<PoiLabelCandidate> candidates,
    required Size viewport,
    List<Rect> reserved = const [],
    double viewportPadding = 6,
    double markerGap = 5,
    double collisionPadding = 2,
  }) {
    if (viewport.isEmpty) return const [];
    final viewportRect = (Offset.zero & viewport).deflate(viewportPadding);
    final ordered = [...candidates]
      ..sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        return priority != 0 ? priority : a.id.compareTo(b.id);
      });
    final occupied = <Rect>[
      ...reserved,
      for (final candidate in ordered)
        candidate.markerRect.inflate(collisionPadding),
    ];
    final result = <PoiLabelPlacement>[];

    for (final candidate in ordered) {
      final marker = candidate.markerRect;
      final label = candidate.labelSize;
      final options = <Rect>[
        Rect.fromLTWH(
          marker.right + markerGap,
          marker.center.dy - label.height / 2,
          label.width,
          label.height,
        ),
        Rect.fromLTWH(
          marker.left - markerGap - label.width,
          marker.center.dy - label.height / 2,
          label.width,
          label.height,
        ),
        Rect.fromLTWH(
          marker.center.dx - label.width / 2,
          marker.top - markerGap - label.height,
          label.width,
          label.height,
        ),
        Rect.fromLTWH(
          marker.center.dx - label.width / 2,
          marker.bottom + markerGap,
          label.width,
          label.height,
        ),
      ];
      Rect? selected;
      for (final option in options) {
        if (!viewportRect.contains(option.topLeft) ||
            !viewportRect.contains(option.bottomRight) ||
            occupied.any((rect) => rect.overlaps(option))) {
          continue;
        }
        selected = option;
        break;
      }
      if (selected == null) continue;
      result.add(PoiLabelPlacement(id: candidate.id, rect: selected));
      occupied.add(selected.inflate(collisionPadding));
    }
    return result;
  }
}
