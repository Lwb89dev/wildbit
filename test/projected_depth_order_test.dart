import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/projected_depth_order.dart';

void main() {
  test('classifies a lower projected ground anchor in front of Bit', () {
    const bit = Offset(180, 240);
    const tree = Offset(20, 260);

    expect(
      ProjectedDepthOrder.belongsToSlice(
        objectFoot: tree,
        pivotFoot: bit,
        slice: ProjectedDepthSlice.inFrontOfPivot,
      ),
      isTrue,
    );
    expect(
      ProjectedDepthOrder.belongsToSlice(
        objectFoot: tree,
        pivotFoot: bit,
        slice: ProjectedDepthSlice.behindPivot,
      ),
      isFalse,
    );
  });

  test('uses projected Y regardless of horizontal position or bearing', () {
    const bit = Offset(100, 100);

    for (final tree in const [Offset(-500, 80), Offset(900, 80)]) {
      expect(
        ProjectedDepthOrder.belongsToSlice(
          objectFoot: tree,
          pivotFoot: bit,
          slice: ProjectedDepthSlice.behindPivot,
        ),
        isTrue,
      );
    }
  });

  test('equal anchors belong to exactly the background slice', () {
    const anchor = Offset(40, 90);
    expect(
      ProjectedDepthOrder.belongsToSlice(
        objectFoot: anchor,
        pivotFoot: anchor,
        slice: ProjectedDepthSlice.behindPivot,
      ),
      isTrue,
    );
    expect(
      ProjectedDepthOrder.belongsToSlice(
        objectFoot: anchor,
        pivotFoot: anchor,
        slice: ProjectedDepthSlice.inFrontOfPivot,
      ),
      isFalse,
    );
  });

  test('sorts projected anchors back-to-front independently of geography', () {
    final anchors = <Offset>[
      const Offset(400, 260),
      const Offset(-20, 80),
      const Offset(70, 180),
    ]..sort((a, b) => ProjectedDepthOrder.compare(firstFoot: a, secondFoot: b));
    expect(anchors.map((point) => point.dy), [80, 180, 260]);
  });

  test(
    'finds the stable foreground boundary without splitting equal depth',
    () {
      final anchors =
          <Offset>[
            const Offset(40, 80),
            const Offset(20, 120),
            const Offset(80, 120),
            const Offset(10, 170),
          ]..sort(
            (a, b) => ProjectedDepthOrder.compare(firstFoot: a, secondFoot: b),
          );

      expect(
        ProjectedDepthOrder.firstInFrontIndex(
          anchors,
          const Offset(0, 120),
          (anchor) => anchor,
        ),
        3,
      );
      expect(
        ProjectedDepthOrder.firstInFrontIndex(
          anchors,
          const Offset(0, 121),
          (anchor) => anchor,
        ),
        3,
      );
    },
  );

  test(
    'uses the bottom edge of a projected footprint as its ground anchor',
    () {
      expect(
        ProjectedDepthOrder.footprintAnchor(const [
          Offset(10, 10),
          Offset(40, 12),
          Offset(38, 30),
          Offset(12, 30),
        ]),
        const Offset(25, 30),
      );
    },
  );
}
