import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const fork = 'third_party/geolocator_android';

  test('Android location fork contains no Google Play Services dependency', () {
    final build = File('$fork/android/build.gradle');
    final manager = File(
      '$fork/android/src/main/java/com/baseflow/geolocator/location/'
      'GeolocationManager.java',
    );
    final fused = File(
      '$fork/android/src/main/java/com/baseflow/geolocator/location/'
      'FusedLocationClient.java',
    );

    expect(Directory(fork).existsSync(), isTrue);
    expect(build.readAsStringSync(), isNot(contains('play-services-location')));
    expect(manager.readAsStringSync(), isNot(contains('com.google.android.gms')));
    expect(fused.existsSync(), isFalse);
  });

  test('WildBit pins the Android location package to the local no-Google fork', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gps = File('lib/location/geolocator_location_service.dart')
        .readAsStringSync();

    expect(
      pubspec,
      contains('geolocator_android:\n    path: third_party/geolocator_android'),
    );
    expect(RegExp(r'forceLocationManager:\s*true').allMatches(gps).length,
        greaterThanOrEqualTo(2));
    expect(gps, contains('forceAndroidLocationManager: Platform.isAndroid'));
  });
}
