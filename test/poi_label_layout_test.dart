import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/poi_label_layout.dart';

void main() {
  test('places labels without covering any marker', () {
    const candidates = [
      PoiLabelCandidate(
        id: 'shelter',
        markerRect: Rect.fromLTWH(80, 80, 24, 24),
        labelSize: Size(70, 18),
        priority: 0,
      ),
      PoiLabelCandidate(
        id: 'water',
        markerRect: Rect.fromLTWH(155, 80, 20, 20),
        labelSize: Size(58, 18),
        priority: 1,
      ),
    ];

    final result = PoiLabelLayout.compose(
      candidates: candidates,
      viewport: const Size(320, 240),
    );
    expect(result, hasLength(2));
    for (final label in result) {
      for (final candidate in candidates) {
        expect(label.rect.overlaps(candidate.markerRect), isFalse);
      }
    }
    expect(result[0].rect.overlaps(result[1].rect), isFalse);
  });

  test('always assigns higher-priority labels first', () {
    const candidates = [
      PoiLabelCandidate(
        id: 'parking',
        markerRect: Rect.fromLTWH(31, 31, 18, 18),
        labelSize: Size(42, 18),
        priority: 2,
      ),
      PoiLabelCandidate(
        id: 'summit',
        markerRect: Rect.fromLTWH(31, 31, 18, 18),
        labelSize: Size(42, 18),
        priority: 0,
      ),
    ];

    final result = PoiLabelLayout.compose(
      candidates: candidates,
      viewport: const Size(100, 80),
      viewportPadding: 0,
    );
    expect(result, isNotEmpty);
    expect(result.first.id, 'summit');
  });

  test('does not place a label inside a reserved UI region', () {
    const reserved = Rect.fromLTWH(0, 0, 200, 50);
    final result = PoiLabelLayout.compose(
      candidates: const [
        PoiLabelCandidate(
          id: 'guidepost',
          markerRect: Rect.fromLTWH(85, 55, 20, 20),
          labelSize: Size(90, 18),
          priority: 0,
        ),
      ],
      viewport: const Size(200, 100),
      reserved: const [reserved],
    );
    for (final label in result) {
      expect(label.rect.overlaps(reserved), isFalse);
    }
  });
}
