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
    // An alpine hut is a building-scale landmark, not a small POI pin. Its
    // visible source is cropped below, so this scale applies to the actual
    // roof-to-foundation artwork while preserving the geographic foot.
    final height = markerSize * (isAlpine ? 1.25 : .86);
    final source = sourceRect(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      shelterType: shelterType,
    );
    final aspect = source.width / source.height;
    final width = height * aspect;
    // Artwork has a small transparent grounding margin. Keep every shelter's
    // actual doorway/base on the same geographic foot instead of centering
    // their source canvases independently.
    return Rect.fromLTWH(foot.dx - width / 2, foot.dy - height, width, height);
  }

  /// Crops transparent grounding rows from the alpine hut at draw time. The
  /// source asset is 48x48, but its visible artwork ends at row 38.
  static Rect sourceRect({
    required int imageWidth,
    required int imageHeight,
    required String? shelterType,
  }) {
    final isAlpine = shelterType == null || shelterType == 'alpine_hut';
    final visibleHeight = isAlpine
        ? (imageHeight * (38 / 48)).round().clamp(1, imageHeight)
        : imageHeight;
    return Rect.fromLTWH(0, 0, imageWidth.toDouble(), visibleHeight.toDouble());
  }
}
