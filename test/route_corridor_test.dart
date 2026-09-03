import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/map_cell_grid.dart';
import 'package:wildbit/data/osm/route_corridor.dart';
import 'package:wildbit/domain/entities/geo_bounds.dart';

void main() {
  test('a single point still yields the cell(s) around it', () {
    final cells = RouteCorridor.cellsCovering(
      const [LatLng(46.0, 11.0)],
      bufferMeters: 400,
    );

    expect(cells, isNotEmpty);
    expect(cells.any((cell) => cell.contains(const LatLng(46.0, 11.0))), isTrue);
  });

  test('a wider buffer never covers fewer cells than a narrower one', () {
    const points = [LatLng(46.0, 11.0), LatLng(46.05, 11.05)];

    final narrow = RouteCorridor.cellsCovering(points, bufferMeters: 150);
    final wide = RouteCorridor.cellsCovering(points, bufferMeters: 800);

    expect(wide.length, greaterThanOrEqualTo(narrow.length));
  });

  test('an L-shaped route stays far below its own bounding-box cost', () {
    // East for ~50km, then north for ~50km: the bounding box over both legs
    // is a full square, but a corridor only needs the two thin strips the
    // hiker actually walks — the square's empty quadrant is never fetched.
    final eastLeg = [
      for (var i = 0; i <= 500; i++) LatLng(46.0, 11.0 + i * 0.001),
    ];
    final northLeg = [
      for (var i = 1; i <= 500; i++) LatLng(46.0 + i * 0.001, 11.5),
    ];
    final points = [...eastLeg, ...northLeg];

    final corridorCells = RouteCorridor.cellsCovering(
      points,
      bufferMeters: 400,
    ).length;

    const metersPerDegree = 111320.0;
    const bufferDegrees = 400 / metersPerDegree;
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final p in points.skip(1)) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    final box = GeoBounds(
      southWest: LatLng(south - bufferDegrees, west - bufferDegrees),
      northEast: LatLng(north + bufferDegrees, east + bufferDegrees),
    );
    final boxCells = MapCellGrid.cellsCovering(box).length;

    expect(corridorCells, lessThan(boxCells));
  });

  test('deduplicates cells shared by nearby resampled points', () {
    final points = [
      for (var i = 0; i <= 20; i++) LatLng(46.0, 11.0 + i * 0.0001),
    ];

    final cells = RouteCorridor.cellsCovering(points, bufferMeters: 400);
    final keys = cells.map(MapCellGrid.keyFor).toSet();

    expect(keys.length, cells.length);
  });

  test('an empty route yields no cells', () {
    expect(RouteCorridor.cellsCovering(const []), isEmpty);
  });
}
