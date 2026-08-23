import 'package:flutter/material.dart';

/// WildBit's own raster-free base layer.
///
/// It deliberately contains no OSM image tile: geographic content is added
/// above it from decoded OSM features, one semantic family at a time. This
/// makes a missing feature visibly "not loaded" rather than silently showing
/// a filtered conventional map beneath the pixel artwork.
class PixelTerrainBaseLayer extends StatelessWidget {
  const PixelTerrainBaseLayer({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF688B42),
          image: DecorationImage(
            image: AssetImage('assets/map/mock/terrain/grass_1.png'),
            repeat: ImageRepeat.repeat,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    ),
  );
}
