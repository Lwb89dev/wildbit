import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/map_rendering/layers/osm_pixel_tree_layer.dart';

void main() {
  testWidgets('mounts Bit before the first depth pivot is available', (
    tester,
  ) async {
    final pivot = ValueNotifier<LatLng?>(null);
    addTearDown(pivot.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(45, 9),
              initialZoom: 16,
            ),
            children: [
              OsmPixelTreeLayer(
                features: const MapFeatureCollection(
                  areas: [],
                  lines: [],
                  pois: [],
                ),
                depthPivot: pivot,
                middleChild: const ColoredBox(
                  key: Key('bit-depth-sentinel'),
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('bit-depth-sentinel')), findsOneWidget);

    pivot.value = const LatLng(45.0001, 9.0001);
    await tester.pump();

    expect(find.byKey(const Key('bit-depth-sentinel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
