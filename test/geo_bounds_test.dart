import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/geo_bounds.dart';

void main() {
  const loaded = GeoBounds(
    southWest: LatLng(44, 9),
    northEast: LatLng(46, 11),
  );

  test('recognises a viewport already covered by loaded map data', () {
    const inner = GeoBounds(
      southWest: LatLng(44.5, 9.5),
      northEast: LatLng(45.5, 10.5),
    );

    expect(loaded.containsBounds(inner), isTrue);
  });

  test('requires a new load when zooming beyond cached map bounds', () {
    const wider = GeoBounds(
      southWest: LatLng(43.9, 8.9),
      northEast: LatLng(46.1, 11.1),
    );

    expect(loaded.containsBounds(wider), isFalse);
  });
}
