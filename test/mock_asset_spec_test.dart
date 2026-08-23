import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/mock/mock_asset_spec.dart';

void main() {
  test('mock asset catalogue has valid ground anchors and variants', () {
    expect(MockAssetCatalog.specs, isNotEmpty);
    expect(
      MockAssetCatalog.specs.map((spec) => spec.kind).toSet(),
      MockAssetKind.values.toSet(),
    );
    for (final spec in MockAssetCatalog.specs) {
      expect(spec.hasGroundAnchor, isTrue, reason: spec.kind.name);
      expect(spec.variantCount, greaterThan(0), reason: spec.kind.name);
      expect(spec.footprint.width, greaterThan(0), reason: spec.kind.name);
      expect(spec.footprint.height, greaterThan(0), reason: spec.kind.name);
    }
  });

  test('trees use only the lower third as their Bit occlusion mask', () {
    for (final kind in [
      MockAssetKind.deciduousTreeSmall,
      MockAssetKind.deciduousTreeLarge,
      MockAssetKind.coniferTree,
      MockAssetKind.coastalTree,
    ]) {
      expect(
        MockAssetCatalog.byKind(kind).occlusionMask,
        OcclusionMask.lowerThird,
      );
    }
  });
}
