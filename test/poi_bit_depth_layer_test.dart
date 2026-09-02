import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/poi.dart';
import 'package:wildbit/domain/enums/poi_type.dart';
import 'package:wildbit/map_rendering/composition/projected_depth_order.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_poi_layer.dart';

void main() {
  testWidgets(
    'splits POIs around Bit depth pivot without duplicate semantics',
    (tester) async {
      final pivot = ValueNotifier<LatLng?>(null);
      addTearDown(pivot.dispose);
      const features = MapFeatureCollection(
        areas: [],
        lines: [],
        pois: [
          Poi(
            id: 'hut',
            name: 'Rifugio test',
            type: PoiType.shelter,
            position: LatLng(45.0002, 9.0002),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(45, 9),
                initialZoom: 16,
              ),
              children: [
                OsmPixelPoiLayer(
                  features: features,
                  depthPivot: pivot,
                  slice: ProjectedDepthSlice.behindPivot,
                  showLabels: false,
                  interactive: false,
                ),
                OsmPixelPoiLayer(
                  features: features,
                  depthPivot: pivot,
                  slice: ProjectedDepthSlice.inFrontOfPivot,
                ),
              ],
            ),
          ),
        ),
      );

      pivot.value = const LatLng(45.0001, 9.0001);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
