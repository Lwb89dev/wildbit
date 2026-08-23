import 'package:flutter/widgets.dart';

import 'pixel_terrain_base_layer.dart';

/// Compatibility wrapper for callers compiled against the old raster layer.
/// It deliberately performs no network request and applies no pixel filter.
@Deprecated('Use PixelTerrainBaseLayer with semantic OSM vector layers.')
class PixelArtTileLayer extends StatelessWidget {
  const PixelArtTileLayer({super.key});

  @override
  Widget build(BuildContext context) => const PixelTerrainBaseLayer();
}
