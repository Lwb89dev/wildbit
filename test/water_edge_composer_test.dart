import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/water_edge_composer.dart';

void main() {
  const composer = WaterEdgeComposer(spacing: 10);
  const lake = [Offset(0, 0), Offset(30, 0), Offset(30, 20), Offset(0, 20)];

  test('creates deterministic placements for each water edge', () {
    final first = composer.compose(
      polygon: lake,
      material: WaterEdgeMaterial.rock,
      chunkSeed: 42,
    );
    final second = composer.compose(
      polygon: lake,
      material: WaterEdgeMaterial.rock,
      chunkSeed: 42,
    );

    expect(first, hasLength(10));
    expect(
      first.map((item) => item.variant),
      second.map((item) => item.variant),
    );
    expect(
      first.every((item) => item.material == WaterEdgeMaterial.rock),
      isTrue,
    );
  });

  test('rejects incomplete geometry', () {
    expect(
      composer.compose(
        polygon: const [Offset.zero, Offset(10, 0)],
        material: WaterEdgeMaterial.grass,
        chunkSeed: 1,
      ),
      isEmpty,
    );
  });

  test('spreads edge modules to respect the placement budget', () {
    const capped = WaterEdgeComposer(spacing: 4, maxPlacements: 4);
    final placements = capped.compose(
      polygon: const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ],
      material: WaterEdgeMaterial.grass,
      chunkSeed: 1,
    );

    expect(placements.length, lessThanOrEqualTo(4));
  });

  test('respects the budget on a coastline with many short OSM edges', () {
    const capped = WaterEdgeComposer(spacing: 2, maxPlacements: 5);
    final placements = capped.compose(
      polygon: const [
        Offset(0, 0),
        Offset(5, 0),
        Offset(10, 1),
        Offset(15, 0),
        Offset(20, 2),
        Offset(20, 20),
        Offset(0, 20),
      ],
      material: WaterEdgeMaterial.rock,
      chunkSeed: 7,
    );

    expect(placements, hasLength(5));
    expect(placements.map((item) => item.position).toSet(), hasLength(5));
  });

  test('keeps a fixed shoreline population across projected zoom sizes', () {
    const small = [
      Offset(0, 0),
      Offset(40, 0),
      Offset(40, 30),
      Offset(0, 30),
    ];
    const large = [
      Offset(0, 0),
      Offset(400, 0),
      Offset(400, 300),
      Offset(0, 300),
    ];
    const composer = WaterEdgeComposer(
      spacing: 24,
      maxPlacements: 18,
      fixedPlacements: 8,
    );
    final smallEdges = composer.compose(
      polygon: small,
      material: WaterEdgeMaterial.rock,
      chunkSeed: 17,
    );
    final largeEdges = composer.compose(
      polygon: large,
      material: WaterEdgeMaterial.rock,
      chunkSeed: 17,
    );

    expect(smallEdges, hasLength(8));
    expect(largeEdges, hasLength(8));
    expect(
      smallEdges.map((edge) => edge.variant),
      orderedEquals(largeEdges.map((edge) => edge.variant)),
    );
  });

  test('normal always points away from water regardless of ring winding', () {
    const clockwise = [
      Offset(0, 0),
      Offset(30, 0),
      Offset(30, 20),
      Offset(0, 20),
    ];
    const counterClockwise = [
      Offset(0, 0),
      Offset(0, 20),
      Offset(30, 20),
      Offset(30, 0),
    ];
    for (final polygon in [clockwise, counterClockwise]) {
      final placements = composer.compose(
        polygon: polygon,
        material: WaterEdgeMaterial.mud,
        chunkSeed: 9,
      );
      expect(
        placements.every(
          (edge) =>
              !_contains(polygon, edge.position + edge.normal * 2) &&
              _contains(polygon, edge.position - edge.normal * 4),
        ),
        isTrue,
      );
    }
  });
}

bool _contains(List<Offset> polygon, Offset point) {
  var inside = false;
  for (
    var index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index++
  ) {
    final a = polygon[index];
    final b = polygon[previous];
    if ((a.dy > point.dy) == (b.dy > point.dy)) continue;
    final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
    if (point.dx < x) inside = !inside;
  }
  return inside;
}
