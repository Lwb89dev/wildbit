import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/route_label_layout.dart';

void main() {
  test('anchors a label only to a real visible path segment', () {
    final anchor = RouteLabelLayout.anchorForPath(const [
      Offset(-20, 100),
      Offset(140, 100),
      Offset(260, 180),
    ], const Size(240, 200));

    expect(anchor, const Offset(60, 100));
  });

  test('does not invent an anchor from short disconnected detail', () {
    final anchor = RouteLabelLayout.anchorForPath(
      const [Offset(40, 40), Offset(45, 42), Offset(50, 45)],
      const Size(200, 120),
      minimumSegmentLength: 20,
    );

    expect(anchor, isNull);
  });

  test('prioritises references and prevents label collisions', () {
    final result = RouteLabelLayout.compose(
      candidates: const [
        RouteLabelCandidate(
          id: 'name-only',
          anchor: Offset(100, 80),
          labelSize: Size(80, 18),
          priority: 1,
        ),
        RouteLabelCandidate(
          id: 'ref',
          anchor: Offset(100, 80),
          labelSize: Size(40, 18),
          priority: 0,
        ),
      ],
      viewport: const Size(220, 160),
    );

    expect(result.first.id, 'ref');
    for (var first = 0; first < result.length; first++) {
      for (var second = first + 1; second < result.length; second++) {
        expect(result[first].rect.overlaps(result[second].rect), isFalse);
      }
    }
  });
}
