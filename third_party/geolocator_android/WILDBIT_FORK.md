# WildBit vendored dependency

This is the MIT-licensed `geolocator_android` fork maintained for Roadstr and
vendored here unchanged from that fork. It is based on `geolocator_android`
5.0.3 and removes Google Play Services location support:

- `FusedLocationClient.java` is absent;
- `GeolocationManager` always creates the AOSP `LocationManagerClient`;
- `play-services-location` is absent from its Android Gradle dependencies.

WildBit keeps `forceLocationManager: true` in every Android position stream
and one-shot request as an explicit regression guard. See
`test/no_google_location_dependency_test.dart`.
