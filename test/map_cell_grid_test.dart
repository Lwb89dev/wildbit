import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/map_cell_grid.dart';
import 'package:wildbit/domain/entities/geo_bounds.dart';

void main() {
  const gps = LatLng(44.42554865498096, 12.211025012657046);
  const gpsViewport = GeoBounds(
    southWest: LatLng(44.41904865498096, 12.202014),
    northEast: LatLng(44.43204865498096, 12.220036),
  );

  test('GPS cell is loaded before neighbouring cells', () {
    final ordered = MapCellGrid.cellsCoveringNearestFirst(gpsViewport);

    expect(ordered, hasLength(4));
    expect(ordered.first.contains(gps), isTrue);
    expect(
      ordered.map(MapCellGrid.keyFor).toSet(),
      MapCellGrid.cellsCovering(gpsViewport).map(MapCellGrid.keyFor).toSet(),
    );
  });

  test('explicit Bit position takes priority over viewport centre', () {
    const bitNearNorthEast = LatLng(44.4318, 12.2198);
    final ordered = MapCellGrid.cellsCoveringPrioritized(
      gpsViewport,
      priority: bitNearNorthEast,
    );

    expect(ordered.first.contains(bitNearNorthEast), isTrue);
  });

  test('bounds ending on a grid edge do not add an extra row or column', () {
    const oneCell = GeoBounds(
      southWest: LatLng(44.42, 12.20),
      northEast: LatLng(44.44, 12.22),
    );

    final cells = MapCellGrid.cellsCovering(oneCell);

    expect(cells, hasLength(1));
    expect(cells.single.southWest.latitude, closeTo(44.42, 1e-12));
    expect(cells.single.southWest.longitude, closeTo(12.20, 1e-12));
    expect(cells.single.northEast.latitude, closeTo(44.44, 1e-12));
    expect(cells.single.northEast.longitude, closeTo(12.22, 1e-12));
  });

  test('one southern cell does not mark the GPS viewport as complete', () {
    final cells = MapCellGrid.cellsCovering(gpsViewport);
    final southernCell = cells.reduce(
      (first, second) =>
          first.southWest.latitude < second.southWest.latitude ? first : second,
    );

    expect(MapCellGrid.isCoveredBy(gpsViewport, [southernCell]), isFalse);
    expect(MapCellGrid.isCoveredBy(gpsViewport, cells), isTrue);
  });
}
