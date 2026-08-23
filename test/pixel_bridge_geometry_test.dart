import 'package:flutter_test/flutter_test.dart';

import 'package:wildbit/map_rendering/composition/pixel_bridge_geometry.dart';

void main() {
  test('uses projected length without applying zoom twice', () {
    final overview = PixelBridgeGeometry.fromProjected(
      start: Offset.zero,
      end: const Offset(40, 0),
      zoom: 8,
    )!;
    final close = PixelBridgeGeometry.fromProjected(
      start: Offset.zero,
      end: const Offset(40, 0),
      zoom: 18,
    )!;

    expect(overview.width, 40);
    expect(close.width, 40);
    expect(close.height, greaterThan(overview.height));
  });

  test('keeps a confirmed short bridge readable at overview zoom', () {
    final geometry = PixelBridgeGeometry.fromProjected(
      start: Offset.zero,
      end: const Offset(2, 2),
      zoom: 7,
    )!;

    expect(geometry.width, 14);
    expect(geometry.height, greaterThanOrEqualTo(7));
    expect(geometry.midSegments, greaterThanOrEqualTo(1));
  });

  test('rejects degenerate projected geometry', () {
    expect(
      PixelBridgeGeometry.fromProjected(
        start: Offset.zero,
        end: Offset.zero,
        zoom: 16,
      ),
      isNull,
    );
  });
}
