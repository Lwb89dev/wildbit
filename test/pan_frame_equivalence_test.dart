import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/test_data/renderer_stress_region.dart';
import 'package:wildbit/data/test_data/test_region.dart';
import 'package:wildbit/domain/entities/geo_fix.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/coastline_topology_composer.dart';
import 'package:wildbit/map_rendering/composition/osm_line_projector.dart';
import 'package:wildbit/map_rendering/composition/projected_depth_order.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_biome_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_bridge_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_coastline_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_contour_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_flower_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_foreground_vegetation_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_geology_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_poi_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_route_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_tree_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_urban_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_water_layer.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_waterway_layer.dart';
import 'package:wildbit/map_rendering/layers/pixel_recorded_track_layer.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';

/// Every pixel layer that reuses projections across a pan must paint the
/// same image as a fresh projection at the destination camera. Artwork is
/// not decoded in widget tests, so layers use their geometric fallbacks:
/// this compares geometry and placement, which is what translation reuse
/// could get wrong.
void main() {
  final features = rendererStressFeatures;
  final coastline = CoastlineTopologyComposer.compose(
    features.lines.where((line) => line.kind == MapFeatureKind.coastline),
  );
  final track = [
    for (var index = 0; index < 40; index++)
      GeoFix(
        position: LatLng(46.064 + index * .0002, 11.115 + index * .00025),
        timestamp: DateTime.utc(2026, 1, 1, 9, 0, index),
      ),
  ];
  final start = testRegionCenter;
  final destination = LatLng(start.latitude + .002, start.longitude - .003);

  setUp(() {
    MapRenderingBudget.resetDeviceProfile();
    MapRenderingBudget.resetFramePressure();
    MapRenderingBudget.setMapInteracting(false);
    // Keep the shared animation clocks from scheduling timers in the test.
    MapRenderingBudget.setMapVisible(false);
  });

  final layers = <String, Widget Function()>{
    'coastline': () => OsmPixelCoastlineLayer(topology: coastline),
    'water': () => OsmPixelWaterLayer(features: features),
    'waterway': () => OsmPixelWaterwayLayer(features: features),
    'biome': () => OsmPixelBiomeLayer(features: features),
    'geology': () => OsmPixelGeologyLayer(features: features),
    'contour': () => OsmPixelContourLayer(features: features),
    'urban': () => OsmPixelUrbanLayer(features: features),
    'route': () => OsmPixelRouteLayer(
      features: features,
      projectionCache: ProjectedLineCache(),
    ),
    'bridge': () => OsmPixelBridgeLayer(features: features),
    'track': () => PixelRecordedTrackLayer(points: track),
    'flower': () => OsmPixelFlowerLayer(features: features),
    'shrub': () => OsmPixelForegroundVegetationLayer(features: features),
    'poi': () => OsmPixelPoiLayer(
      features: features,
      slice: ProjectedDepthSlice.all,
      showLabels: false,
      interactive: false,
    ),
    'tree': () => OsmPixelTreeLayer(features: features),
  };

  Widget scene(
    MapController controller,
    LatLng center,
    double rotation,
    Widget Function() layer,
  ) {
    return MaterialApp(
      home: DefaultAssetBundle(
        // Artwork never loads, so both renders use the geometric fallbacks.
        bundle: _NoArtworkBundle(),
        child: RepaintBoundary(
          key: const Key('scene'),
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.5,
              initialRotation: rotation,
            ),
            children: [layer()],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> capture(WidgetTester tester) async {
    final boundary =
        tester.renderObject(find.byKey(const Key('scene')))
            as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  for (final rotation in const [0.0, 30.0]) {
    for (final entry in layers.entries) {
      testWidgets('${entry.key} pans like a fresh projection ($rotation°)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(420, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final panned = MapController();
        addTearDown(panned.dispose);
        await tester.pumpWidget(scene(panned, start, rotation, entry.value));
        await tester.pump();
        // Several small moves, like a drag, then the final destination.
        for (var step = 1; step <= 4; step++) {
          panned.move(
            LatLng(
              start.latitude +
                  (destination.latitude - start.latitude) * step / 4,
              start.longitude +
                  (destination.longitude - start.longitude) * step / 4,
            ),
            15.5,
          );
          await tester.pump();
        }
        final reused = await capture(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        final fresh = MapController();
        addTearDown(fresh.dispose);
        await tester.pumpWidget(
          scene(fresh, destination, rotation, entry.value),
        );
        await tester.pump();
        final direct = await capture(tester);

        expect(reused.length, direct.length);
        var differing = 0;
        for (var index = 0; index < reused.length; index += 4) {
          var delta = 0;
          for (var channel = 0; channel < 4; channel++) {
            final difference =
                (reused[index + channel] - direct[index + channel]).abs();
            if (difference > delta) delta = difference;
          }
          if (delta > 8) differing++;
        }
        expect(differing, 0, reason: '${entry.key}: pixels differ');
      });
    }
  }
}

class _NoArtworkBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('artwork disabled in this test: $key'));
}
