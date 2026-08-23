import 'dart:math' as math;
import 'dart:ui';

class RouteLabelCandidate {
  const RouteLabelCandidate({
    required this.id,
    required this.anchor,
    required this.labelSize,
    required this.priority,
  });

  final String id;
  final Offset anchor;
  final Size labelSize;
  final int priority;
}

class RouteLabelPlacement {
  const RouteLabelPlacement({
    required this.id,
    required this.anchor,
    required this.rect,
  });

  final String id;
  final Offset anchor;
  final Rect rect;
}

abstract final class RouteLabelLayout {
  /// Selects a visible, sufficiently long real segment. No proximity between
  /// distinct OSM ways is ever used to invent a route continuation.
  static Offset? anchorForPath(
    List<Offset> points,
    Size viewport, {
    double minimumSegmentLength = 28,
  }) {
    if (points.length < 2 || viewport.isEmpty) return null;
    final visible = (Offset.zero & viewport).deflate(8);
    final viewportCenter = visible.center;
    Offset? best;
    var bestScore = double.infinity;
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      final length = (end - start).distance;
      if (length < minimumSegmentLength) continue;
      final midpoint = Offset.lerp(start, end, .5)!;
      if (!visible.contains(midpoint)) continue;
      final distance = (midpoint - viewportCenter).distance;
      final score = distance - math.min(length, 180) * .18;
      if (score < bestScore) {
        best = midpoint;
        bestScore = score;
      }
    }
    return best;
  }

  static List<RouteLabelPlacement> compose({
    required List<RouteLabelCandidate> candidates,
    required Size viewport,
    List<Rect> reserved = const [],
  }) {
    if (viewport.isEmpty) return const [];
    final bounds = (Offset.zero & viewport).deflate(6);
    final ordered = [...candidates]
      ..sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        return priority != 0 ? priority : a.id.compareTo(b.id);
      });
    final occupied = [...reserved];
    final result = <RouteLabelPlacement>[];
    for (final candidate in ordered) {
      final size = candidate.labelSize;
      final anchor = candidate.anchor;
      final options = [
        Rect.fromLTWH(
          anchor.dx - size.width / 2,
          anchor.dy - size.height - 7,
          size.width,
          size.height,
        ),
        Rect.fromLTWH(
          anchor.dx - size.width / 2,
          anchor.dy + 7,
          size.width,
          size.height,
        ),
        Rect.fromLTWH(
          anchor.dx + 7,
          anchor.dy - size.height / 2,
          size.width,
          size.height,
        ),
        Rect.fromLTWH(
          anchor.dx - size.width - 7,
          anchor.dy - size.height / 2,
          size.width,
          size.height,
        ),
      ];
      Rect? selected;
      for (final option in options) {
        if (!bounds.contains(option.topLeft) ||
            !bounds.contains(option.bottomRight) ||
            occupied.any((rect) => rect.overlaps(option.inflate(2)))) {
          continue;
        }
        selected = option;
        break;
      }
      if (selected == null) continue;
      result.add(
        RouteLabelPlacement(id: candidate.id, anchor: anchor, rect: selected),
      );
      occupied.add(selected.inflate(2));
    }
    return result;
  }
}
