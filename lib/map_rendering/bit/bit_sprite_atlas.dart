import '../../domain/enums/direction8.dart';

/// Maps Bit's animation/direction state to asset paths. All 8 walk
/// directions intentionally use the same authored walk cycle. The original
/// directional exports changed Bit's trekking pole between hands; keeping one
/// consistent right-hand-pole cycle is preferable until complete directional
/// art exists.
abstract final class BitSpriteAtlas {
  static const _base = 'assets/sprites/bit';

  // A 16-frame loop keeps the feet and the trekking pole in phase instead of
  // repeatedly snapping between a few poses.
  static const int walkFrameCount = 16;
  static const int mapFrameCount = 12;

  static String walkFrame(Direction8 direction, int frameIndex1Based) {
    return '$_base/walk_s_${frameIndex1Based.toString().padLeft(2, '0')}.png';
  }

  static String mapFrame(int frameIndex1Based) {
    return '$_base/map_$frameIndex1Based.png';
  }

  static const String standing = '$_base/standing.png';

  static List<String> get allAssetPaths => [
    standing,
    for (var f = 1; f <= mapFrameCount; f++) mapFrame(f),
    for (final d in Direction8.values)
      for (var f = 1; f <= walkFrameCount; f++) walkFrame(d, f),
  ];
}
