import 'package:flutter/material.dart';

/// Native 16×16-pixel terrain textures for the fixed valley mock.
///
/// This is intentionally a small proof of the eventual chunk compositor:
/// imagery is drawn as source pixel art and only scaled by the scene's outer
/// [FittedBox], never by filtering a conventional map tile.
class MockTerrainTextureLayer extends StatelessWidget {
  const MockTerrainTextureLayer({super.key});

  static const _grass = AssetImage('assets/map/mock/terrain/grass_1.png');
  @override
  Widget build(BuildContext context) => const DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: _grass,
          repeat: ImageRepeat.repeat,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: SizedBox.expand(),
    );
}
