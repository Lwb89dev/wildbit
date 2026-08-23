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
}
