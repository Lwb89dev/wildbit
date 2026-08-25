import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/map_rendering/composition/osm_multipolygon_composer.dart';

void main() {
  test('joins split and reversed outer ways and assigns an inner hole', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(0, 0), LatLng(0, 2)],
      ),
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(2, 0), LatLng(2, 2), LatLng(0, 2)],
      ),
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(2, 0), LatLng(0, 0)],
      ),
      const MultipolygonMember(
        role: 'inner',
        points: [
          LatLng(.5, .5),
          LatLng(1.5, .5),
          LatLng(1.5, 1.5),
          LatLng(.5, 1.5),
          LatLng(.5, .5),
        ],
      ),
    ]);

    expect(result.isValid, isTrue);
    expect(result.polygons, hasLength(1));
    expect(result.polygons.single.outer, hasLength(4));
    expect(result.polygons.single.holes, hasLength(1));
  });

  test('rejects an unclosed boundary instead of inventing a polygon', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(0, 0), LatLng(0, 1)],
      ),
    ]);

    expect(result.polygons, isEmpty);
    expect(result.issues, isNotEmpty);
  });

  test('assigns a hole to the smallest containing outer ring', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(0, 0),
          LatLng(0, 10),
          LatLng(10, 10),
          LatLng(10, 0),
          LatLng(0, 0),
        ],
      ),
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(2, 2),
          LatLng(2, 8),
          LatLng(8, 8),
          LatLng(8, 2),
          LatLng(2, 2),
        ],
      ),
      const MultipolygonMember(
        role: 'inner',
        points: [
          LatLng(3, 3),
          LatLng(3, 4),
          LatLng(4, 4),
          LatLng(4, 3),
          LatLng(3, 3),
        ],
      ),
    ]);

    expect(result.isValid, isTrue);
    expect(result.polygons, hasLength(2));
    expect(result.polygons.first.holes, isEmpty);
    expect(result.polygons.last.holes, hasLength(1));
  });

  test('rejects a self-intersecting ring instead of filling a bow tie', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(45, 9),
          LatLng(45.02, 9.02),
          LatLng(45, 9.02),
          LatLng(45.02, 9),
          LatLng(45, 9),
        ],
      ),
    ]);

    expect(result.isComplete, isFalse);
    expect(result.issues, contains('outer multipolygon ring self-intersects'));
  });

  test('rejects repeated interior vertices', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(45, 9),
          LatLng(45.02, 9),
          LatLng(45.02, 9.02),
          LatLng(45.02, 9),
          LatLng(45, 9.02),
          LatLng(45, 9),
        ],
      ),
    ]);

    expect(result.isComplete, isFalse);
    expect(
      result.issues,
      contains('outer multipolygon ring repeats an interior vertex'),
    );
  });
}
