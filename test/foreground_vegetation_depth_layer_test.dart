import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/projected_depth_order.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_foreground_vegetation_layer.dart';

void main() {
  testWidgets(
    'splits low vegetation around Bit at a rotated camera without duplicates',
    (tester) async {
      final pivot = ValueNotifier<LatLng?>(null);
      addTearDown(pivot.dispose);
      const features = MapFeatureCollection(
        areas: [
          AreaFeature(
            kind: MapFeatureKind.forest,
            sourceId: 'forest-depth-test',
            ring: [
              LatLng(44.9996, 8.9996),
              LatLng(45.0006, 8.9996),
              LatLng(45.0006, 9.0006),
              LatLng(44.9996, 9.0006),
            ],
          ),
        ],
        lines: [],
        pois: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(45, 9),
                initialZoom: 16,
                initialRotation: 90,
              ),
              children: [
                OsmPixelForegroundVegetationLayer(
                  features: features,
                  depthPivot: pivot,
                  slice: ProjectedDepthSlice.behindPivot,
                ),
                OsmPixelForegroundVegetationLayer(
                  features: features,
                  depthPivot: pivot,
                  slice: ProjectedDepthSlice.inFrontOfPivot,
                ),
              ],
            ),
          ),
        ),
      );

      pivot.value = const LatLng(45, 9);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
