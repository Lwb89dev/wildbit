/// Contracts for the temporary, geometry-first asset kit used by the pixel-map
/// prototype.  These values describe world placement independently from the
/// eventual PNG artwork, so replacing silhouettes with final art cannot change
/// collision or draw-order behaviour.
library;

enum MockAssetKind {
  deciduousTreeSmall,
  deciduousTreeLarge,
  coniferTree,
  coastalTree,
  shrubRound,
  shrubWide,
  shrubRiverside,
  flowerClusterA,
  flowerClusterB,
  pebble,
  boulder,
  rockBlock,
  wetRock,
  outcrop,
  reeds,
  guidepostSingle,
  guidepostMulti,
  trailMarkerLow,
  hutBivouac,
  hutAlpine,
  hutShed,
  bridgeFootStart,
  bridgeFootMiddle,
  bridgeFootEnd,
  bridgeTrackStart,
  bridgeTrackMiddle,
  bridgeTrackEnd,
  fordStones,
}

/// Fixed composition groups from the renderer specification.
enum MapDrawLayer {
  terrainBase,
  shoreAndStructuralRock,
  backgroundVegetation,
  paths,
  foregroundVegetation,
  poiAndStructures,
  dynamicWorld,
  interface,
}

/// A pixel coordinate inside an asset canvas. The map projection snaps this
/// anchor to the current logical pixel grid before drawing.
class PixelAnchor {
  const PixelAnchor(this.x, this.y);

  final int x;
  final int y;
}

/// Ground-space reservation in logical pixels, centred on the asset anchor.
class PixelFootprint {
  const PixelFootprint({required this.width, required this.height});

  final int width;
  final int height;
}

/// Which vertical portion of an asset can be drawn in front of Bit.
enum OcclusionMask { none, lowerThird, full }

class MockAssetSpec {
  const MockAssetSpec({
    required this.kind,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.anchor,
    required this.footprint,
    required this.layer,
    required this.occlusionMask,
    this.variantCount = 1,
  });

  final MockAssetKind kind;
  final int canvasWidth;
  final int canvasHeight;
  final PixelAnchor anchor;
  final PixelFootprint footprint;
  final MapDrawLayer layer;
  final OcclusionMask occlusionMask;
  final int variantCount;

  bool get hasGroundAnchor =>
      anchor.x >= 0 &&
      anchor.x < canvasWidth &&
      anchor.y >= 0 &&
      anchor.y < canvasHeight;
}

/// Canonical specifications for the first mock scene. All instances are
/// immutable so a chunk may safely reuse them while it composes sprites.
abstract final class MockAssetCatalog {
  /// Native artwork contracts used by both the desktop mock and the OSM
  /// compositor. Keeping these paths beside the geometry spec prevents a
  /// sprite replacement from silently drifting away from its anchor.
  static const treeArtwork = <MockAssetKind, String>{
    MockAssetKind.deciduousTreeSmall:
        'assets/map/mock/objects/tree_deciduous_s.png',
    MockAssetKind.deciduousTreeLarge:
        'assets/map/mock/objects/tree_deciduous_l.png',
    MockAssetKind.coniferTree: 'assets/map/mock/objects/tree_conifer.png',
    MockAssetKind.coastalTree: 'assets/map/mock/objects/tree_coastal.png',
  };

  static const treeCanvasSize = <MockAssetKind, (int width, int height)>{
    MockAssetKind.deciduousTreeSmall: (32, 48),
    MockAssetKind.deciduousTreeLarge: (32, 48),
    MockAssetKind.coniferTree: (32, 48),
    MockAssetKind.coastalTree: (32, 48),
  };

  static const specs = <MockAssetSpec>[
    MockAssetSpec(
      kind: MockAssetKind.deciduousTreeSmall,
      canvasWidth: 24,
      canvasHeight: 32,
      anchor: PixelAnchor(12, 30),
      footprint: PixelFootprint(width: 12, height: 8),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.deciduousTreeLarge,
      canvasWidth: 32,
      canvasHeight: 48,
      anchor: PixelAnchor(16, 47),
      footprint: PixelFootprint(width: 16, height: 10),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.coniferTree,
      canvasWidth: 32,
      canvasHeight: 48,
      anchor: PixelAnchor(16, 46),
      footprint: PixelFootprint(width: 14, height: 8),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.coastalTree,
      canvasWidth: 32,
      canvasHeight: 40,
      anchor: PixelAnchor(16, 38),
      footprint: PixelFootprint(width: 16, height: 9),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.shrubRound,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 12, height: 6),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 6,
    ),
    MockAssetSpec(
      kind: MockAssetKind.shrubWide,
      canvasWidth: 24,
      canvasHeight: 16,
      anchor: PixelAnchor(12, 14),
      footprint: PixelFootprint(width: 20, height: 6),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 6,
    ),
    MockAssetSpec(
      kind: MockAssetKind.shrubRiverside,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 12, height: 6),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 6,
    ),
    MockAssetSpec(
      kind: MockAssetKind.flowerClusterA,
      canvasWidth: 8,
      canvasHeight: 8,
      anchor: PixelAnchor(4, 7),
      footprint: PixelFootprint(width: 6, height: 3),
      layer: MapDrawLayer.backgroundVegetation,
      occlusionMask: OcclusionMask.none,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.flowerClusterB,
      canvasWidth: 8,
      canvasHeight: 8,
      anchor: PixelAnchor(4, 7),
      footprint: PixelFootprint(width: 6, height: 3),
      layer: MapDrawLayer.backgroundVegetation,
      occlusionMask: OcclusionMask.none,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.pebble,
      canvasWidth: 8,
      canvasHeight: 8,
      anchor: PixelAnchor(4, 6),
      footprint: PixelFootprint(width: 6, height: 3),
      layer: MapDrawLayer.shoreAndStructuralRock,
      occlusionMask: OcclusionMask.none,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.boulder,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 12, height: 7),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.rockBlock,
      canvasWidth: 32,
      canvasHeight: 24,
      anchor: PixelAnchor(16, 22),
      footprint: PixelFootprint(width: 28, height: 9),
      layer: MapDrawLayer.foregroundVegetation,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.wetRock,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 12, height: 7),
      layer: MapDrawLayer.shoreAndStructuralRock,
      occlusionMask: OcclusionMask.full,
      variantCount: 2,
    ),
    MockAssetSpec(
      kind: MockAssetKind.outcrop,
      canvasWidth: 48,
      canvasHeight: 32,
      anchor: PixelAnchor(24, 30),
      footprint: PixelFootprint(width: 44, height: 12),
      layer: MapDrawLayer.shoreAndStructuralRock,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.reeds,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 12, height: 5),
      layer: MapDrawLayer.backgroundVegetation,
      occlusionMask: OcclusionMask.lowerThird,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.guidepostSingle,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 8, height: 5),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.guidepostMulti,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 8, height: 5),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.trailMarkerLow,
      canvasWidth: 8,
      canvasHeight: 12,
      anchor: PixelAnchor(4, 10),
      footprint: PixelFootprint(width: 6, height: 3),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 4,
    ),
    MockAssetSpec(
      kind: MockAssetKind.hutBivouac,
      canvasWidth: 32,
      canvasHeight: 32,
      anchor: PixelAnchor(16, 30),
      footprint: PixelFootprint(width: 28, height: 12),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 1,
    ),
    MockAssetSpec(
      kind: MockAssetKind.hutAlpine,
      canvasWidth: 48,
      canvasHeight: 48,
      anchor: PixelAnchor(24, 46),
      footprint: PixelFootprint(width: 44, height: 16),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 1,
    ),
    MockAssetSpec(
      kind: MockAssetKind.hutShed,
      canvasWidth: 32,
      canvasHeight: 32,
      anchor: PixelAnchor(16, 30),
      footprint: PixelFootprint(width: 28, height: 12),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 1,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeFootStart,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 16, height: 8),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeFootMiddle,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 16, height: 8),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 3,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeFootEnd,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 16, height: 8),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeTrackStart,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 16, height: 16),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeTrackMiddle,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 16, height: 16),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
      variantCount: 3,
    ),
    MockAssetSpec(
      kind: MockAssetKind.bridgeTrackEnd,
      canvasWidth: 16,
      canvasHeight: 24,
      anchor: PixelAnchor(8, 22),
      footprint: PixelFootprint(width: 16, height: 16),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.full,
    ),
    MockAssetSpec(
      kind: MockAssetKind.fordStones,
      canvasWidth: 16,
      canvasHeight: 16,
      anchor: PixelAnchor(8, 14),
      footprint: PixelFootprint(width: 16, height: 8),
      layer: MapDrawLayer.poiAndStructures,
      occlusionMask: OcclusionMask.none,
      variantCount: 3,
    ),
  ];

  static MockAssetSpec byKind(MockAssetKind kind) =>
      specs.firstWhere((spec) => spec.kind == kind);
}
