import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wildbit/app/app.dart';
import 'package:wildbit/app/app_providers.dart';
import 'package:wildbit/location/simulated_location_service.dart';

void main() {
  testWidgets('WildBit app boots to the map screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'wildbit.onboarding.v1': true});
    final locationService = SimulatedLocationService(
      path: const [LatLng(46.07, 11.12), LatLng(46.071, 11.121)],
    );

    await tester.pumpWidget(
      WildBitProviders(
        locationService: locationService,
        databaseKey: 'a' * 64,
        child: WildBitApp(locationService: locationService),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.map), findsOneWidget);
    expect(
      find.byType(TileLayer),
      findsNothing,
      reason: 'Offline raster maps must not mount behind the HD2D map.',
    );

    locationService.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
