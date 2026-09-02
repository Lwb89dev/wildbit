import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Keeps only the small, high-frequency map artwork decoded across a tab
/// round-trip. Full map layers and their GPU render targets are still allowed
/// to disappear when the Map tab is unmounted.
abstract final class MapVisualAssetWarmup {
  static const essentialAssets = <String>[
    'assets/map/mock/terrain/grass_1.png',
    'assets/map/mock/terrain/grass_2.png',
    'assets/map/mock/terrain/forest_floor.png',
    'assets/map/mock/terrain/rock_generated_1.png',
    'assets/map/mock/terrain/snow_base_1.png',
    'assets/map/mock/terrain/water_still_1.png',
    'assets/map/mock/terrain/water_still_2.png',
    'assets/map/mock/terrain/water_still_3.png',
    'assets/map/mock/terrain/water_flow.png',
    'assets/map/mock/terrain/shore_grass.png',
    'assets/map/mock/terrain/shore_rock_detail.png',
    'assets/map/mock/terrain/shore_sand_bank.png',
    'assets/map/mock/terrain/shore_mud_bank.png',
    'assets/map/mock/terrain/trail_base_1.png',
    'assets/map/mock/terrain/trail_base_2.png',
    'assets/map/mock/terrain/track_base_1.png',
    'assets/map/mock/terrain/track_base_2.png',
    'assets/map/mock/terrain/rock_base.png',
    'assets/map/mock/terrain/sand_base.png',
    'assets/map/mock/terrain/ford_stones.png',
    'assets/map/mock/objects/tree_deciduous_s.png',
    'assets/map/mock/objects/tree_deciduous_l.png',
    'assets/map/mock/objects/tree_conifer.png',
    'assets/map/mock/objects/shrub_round.png',
    'assets/map/mock/objects/shrub_wide.png',
    'assets/map/mock/structures/boulder.png',
    'assets/map/mock/structures/hut_alpine.png',
    'assets/map/mock/structures/hut_bivouac.png',
    'assets/map/mock/structures/guidepost_multi.png',
    'assets/map/mock/structures/bridge_foot_horizontal_v2.png',
  ];

  static Future<void>? _warmup;
  // AssetImage already owns an ImageCache, but its entries are evictable and
  // each visual layer used to start an independent ImageStream on a Map tab
  // remount. Keep just one in-flight/resolved handle per compact raster asset
  // so routes, water and structures join the same decode work.
  static final Map<String, Future<ui.Image>> _resolvedImages = {};

  /// Starts after the first shell frame, never blocks first map paint, and is
  /// intentionally idempotent across all future tab switches.
  static Future<void> warmup(BuildContext context) {
    final ongoing = _warmup;
    if (ongoing != null) return ongoing;
    _warmup = Future.wait<void>([
      for (final asset in essentialAssets) _warmAsset(context, asset),
    ]).then<void>((_) {});
    return _warmup!;
  }

  static Future<void> _warmAsset(BuildContext context, String asset) =>
      resolveImage(
        context,
        asset,
      ).then<void>((_) {}, onError: (error, stackTrace) {});

  /// Resolves a native raster image once for the whole map composition.
  ///
  /// Callers still decide whether to create a shader, atlas or simple sprite
  /// from it. This cache only deduplicates decoding; it never contains map
  /// geometry or a camera-dependent render target.
  static Future<ui.Image> resolveImage(BuildContext context, String asset) {
    final existing = _resolvedImages[asset];
    if (existing != null) return existing;

    final completer = Completer<ui.Image>();
    final stream = AssetImage(
      asset,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        stream.removeListener(listener);
        completer.complete(image.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    final future = completer.future;
    _resolvedImages[asset] = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (error, stackTrace) {
          // Do not cache a failed optional asset forever: a later Map state
          // can retry once storage/asset pressure has subsided.
          if (identical(_resolvedImages[asset], future)) {
            _resolvedImages.remove(asset);
          }
        },
      ),
    );
    return future;
  }

  /// Lets the next Map mount decode the compact essentials again after the
  /// operating system reports memory pressure. The renderer never calls this
  /// during ordinary tab switches, so returning to the map remains warm.
  static void releaseForMemoryPressure() {
    _warmup = null;
    _resolvedImages.clear();
  }
}
