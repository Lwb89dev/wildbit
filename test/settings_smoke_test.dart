import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wildbit/app/app.dart';
import 'package:wildbit/app/app_providers.dart';
import 'package:wildbit/location/simulated_location_service.dart';

void main() {
  testWidgets('Settings screen opens without exceptions', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'wildbit.onboarding.v1': true,
      'wildbit.locale': 'it',
    });
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

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Impostazioni'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Scuro'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Identità Nostr'), 200);
    await tester.pump();
    expect(find.text('Identità Nostr'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.textContaining('Sostieni lo sviluppo'),
      200,
    );
    await tester.pump();
    await tester.tap(find.textContaining('Sostieni lo sviluppo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    locationService.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
