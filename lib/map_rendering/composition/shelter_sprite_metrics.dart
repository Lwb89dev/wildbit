import 'dart:ui';

/// Keeps shelter artwork on one ground plane while allowing an alpine hut to
/// read larger than a small wilderness bivouac.
abstract final class ShelterSpriteMetrics {
  static Rect destination({
    required Offset foot,
    required double markerSize,
    required int imageWidth,
    required int imageHeight,
    required String? shelterType,
  }) {
    final isAlpine = shelterType == null || shelterType == 'alpine_hut';
    final height = markerSize * (isAlpine ? 1.08 : .86);
    final aspect = imageWidth / imageHeight;
    final width = height * aspect;
    // Artwork has a small transparent grounding margin. Keep every shelter's
    // actual doorway/base on the same geographic foot instead of centering
    // their source canvases independently.
    final baseline = height;
    return Rect.fromLTWH(
      foot.dx - width / 2,
      foot.dy - baseline,
      width,
      height,
    );
  }
}
