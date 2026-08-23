import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wildbit/app/app.dart';
import 'package:wildbit/app/app_providers.dart';
import 'package:wildbit/location/simulated_location_service.dart';

void main() {
  testWidgets(
    'onboarding explicitly requests location before entering WildBit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
      await tester.pumpAndSettle();

      expect(find.text('Inizia il viaggio'), findsOneWidget);
      await tester.tap(find.text('Inizia il viaggio'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Consenti la posizione'));
      await tester.pumpAndSettle();
      expect(find.text('Posizione consentita'), findsOneWidget);

      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apri WildBit'));
      // The map keeps Bit's animation ticker active, so it intentionally
      // never reaches a globally settled frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.map), findsOneWidget);

      locationService.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
