import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:wildbit/domain/entities/geo_fix.dart';
import 'package:wildbit/location/location_service.dart';
import 'package:wildbit/map_rendering/bit/bit_animation_controller.dart';
import 'package:wildbit/map_rendering/bit/bit_map_layer.dart';

void main() {
  testWidgets('does not open a GPS stream before permission is granted', (
    tester,
  ) async {
    final service = _DeniedLocationService();
    final controller = BitAnimationController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(46.07, 11.12),
            initialZoom: 16,
          ),
          children: [
            BitMapLayer(locationService: service, controller: controller),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(service.streamOpened, isFalse);
  });
}

class _DeniedLocationService implements LocationService {
  bool streamOpened = false;

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<GeoFix?> getCurrentPosition() async => null;

  @override
  Stream<GeoFix> get positionStream {
    streamOpened = true;
    return const Stream<GeoFix>.empty();
  }
}
