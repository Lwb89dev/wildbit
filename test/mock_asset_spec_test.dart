import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/mock/mock_environment_sprite_layer.dart';
import 'package:wildbit/map_rendering/mock/mock_asset_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('tree artwork matches the native canvas contract', () async {
    for (final entry in MockAssetCatalog.treeArtwork.entries) {
      final bytes = (await rootBundle.load(entry.value)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final expected = MockAssetCatalog.treeCanvasSize[entry.key]!;
      expect(frame.image.width, expected.$1, reason: entry.value);
      expect(frame.image.height, expected.$2, reason: entry.value);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('mock vegetation placements stay inside the logical scene', () {
    expect(MockEnvironmentSpriteLayer.placementsFitScene, isTrue);
  });
}
