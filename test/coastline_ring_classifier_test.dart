import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/coastline_ring_classifier.dart';

void main() {
  test('classifies nested rings as island and water hole', () {
    final rings = CoastlineRingClassifier.classify([
      const [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
      const [Offset(25, 25), Offset(75, 25), Offset(75, 75), Offset(25, 75)],
    ]);

    expect(rings, hasLength(2));
    expect(rings.first.depth, 0);
    expect(rings.first.role, CoastlineRingRole.outerIsland);
    expect(rings.last.depth, 1);
    expect(rings.last.role, CoastlineRingRole.nestedWaterHole);
  });

  test('keeps disjoint islands at the same containment depth', () {
    final rings = CoastlineRingClassifier.classify([
      const [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
      const [Offset(20, 0), Offset(30, 0), Offset(30, 10), Offset(20, 10)],
    ]);

    expect(rings.map((ring) => ring.depth), everyElement(0));
    expect(
      rings.map((ring) => ring.role),
      everyElement(CoastlineRingRole.outerIsland),
    );
  });
}
