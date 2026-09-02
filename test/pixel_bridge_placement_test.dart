import 'package:flutter_test/flutter_test.dart';

import 'package:wildbit/map_rendering/composition/pixel_bridge_placement.dart';

void main() {
  test('anchors both bridge ends outside the water polygon', () {
    const polygon = <Offset>[
      Offset(10, 0),
      Offset(30, 0),
      Offset(30, 40),
      Offset(10, 40),
    ];
    final placement = PixelBridgePlacement.fromWaterPolygon(
      polygon: polygon,
      center: const Offset(20, 20),
      direction: const Offset(1, 0),
      shoreMargin: 2,
    );

    expect(placement, isNotNull);
    expect(placement!.start.dx, 8);
    expect(placement.end.dx, 32);
    expect(placement.start.dy, 20);
    expect(placement.end.dy, 20);
  });

  test('rejects an axis that does not cross the water', () {
    final placement = PixelBridgePlacement.fromWaterPolygon(
      polygon: const [
        Offset(10, 0),
        Offset(30, 0),
        Offset(30, 40),
        Offset(10, 40),
      ],
      center: const Offset(5, 20),
      direction: const Offset(0, 1),
    );

    expect(placement, isNull);
  });

  test('does not span a land island inside a water polygon', () {
    final placement = PixelBridgePlacement.fromWaterPolygon(
      polygon: const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 40),
        Offset(0, 40),
      ],
      holes: const [
        [Offset(40, 10), Offset(60, 10), Offset(60, 30), Offset(40, 30)],
      ],
      center: const Offset(20, 20),
      direction: const Offset(1, 0),
      shoreMargin: 0,
    );

    expect(placement, isNotNull);
    expect(placement!.start.dx, 0);
    expect(placement.end.dx, 40);
  });

  test('selects the nearest water interval for an off-centre bridge way', () {
    final placement = PixelBridgePlacement.fromWaterPolygon(
      polygon: const [
        Offset(10, 0),
        Offset(30, 0),
        Offset(30, 40),
        Offset(10, 40),
      ],
      center: const Offset(5, 20),
      direction: const Offset(1, 0),
      shoreMargin: 2,
    );

    expect(placement, isNotNull);
    expect(placement!.start.dx, 8);
    expect(placement.end.dx, 32);
  });

  test('rejects a water interval too far from the finite bridge way', () {
    final placement = PixelBridgePlacement.fromWaterPolygon(
      polygon: const [
        Offset(100, 0),
        Offset(140, 0),
        Offset(140, 40),
        Offset(100, 40),
      ],
      center: const Offset(10, 20),
      direction: const Offset(20, 0),
      maximumAxisGap: 18,
    );

    expect(placement, isNull);
  });

  test('measures distance from the original way to an anchored bridge', () {
    const placement = PixelBridgePlacement(
      start: Offset(10, 20),
      end: Offset(30, 20),
    );
    expect(placement.distanceTo(const Offset(20, 20)), 0);
    expect(placement.distanceTo(const Offset(40, 20)), 10);
  });
}
