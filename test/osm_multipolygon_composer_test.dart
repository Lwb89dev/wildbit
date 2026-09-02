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

  test('rejects an ambiguous endpoint instead of choosing a branch', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(0, 0), LatLng(0, 1)],
      ),
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(0, 1), LatLng(1, 1)],
      ),
      const MultipolygonMember(
        role: 'outer',
        points: [LatLng(0, 1), LatLng(-1, 1)],
      ),
    ]);

    expect(result.isComplete, isFalse);
    expect(result.issues, contains('outer multipolygon endpoint is ambiguous'));
  });

  test('rejects unknown member roles and incomplete geometry', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(role: 'side', points: []),
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(0, 0),
          LatLng(0, 1),
          LatLng(1, 1),
          LatLng(1, 0),
          LatLng(0, 0),
        ],
      ),
    ]);

    expect(result.isComplete, isFalse);
    expect(
      result.issues,
      contains('multipolygon contains an unsupported member role'),
    );
    expect(
      result.issues,
      contains('multipolygon contains a member without usable geometry'),
    );
  });

  test('supports a water multipolygon crossing the antimeridian', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(10, 179),
          LatLng(10, -179),
          LatLng(12, -179),
          LatLng(12, 179),
          LatLng(10, 179),
        ],
      ),
      const MultipolygonMember(
        role: 'inner',
        points: [
          LatLng(10.5, 179.5),
          LatLng(10.5, -179.5),
          LatLng(11.5, -179.5),
          LatLng(11.5, 179.5),
          LatLng(10.5, 179.5),
        ],
      ),
    ]);

    expect(result.isComplete, isTrue);
    expect(result.polygons.single.holes, hasLength(1));
  });

  test('rejects an inner ring touching the outer shoreline', () {
    final result = OsmMultipolygonComposer.compose([
      const MultipolygonMember(
        role: 'outer',
        points: [
          LatLng(0, 0),
          LatLng(0, 4),
          LatLng(4, 4),
          LatLng(4, 0),
          LatLng(0, 0),
        ],
      ),
      const MultipolygonMember(
        role: 'inner',
        points: [
          LatLng(0, 1),
          LatLng(1, 1),
          LatLng(1, 2),
          LatLng(0, 2),
          LatLng(0, 1),
        ],
      ),
    ]);

    expect(result.isComplete, isFalse);
    expect(
      result.issues,
      contains('an inner ring touches or crosses an outer ring'),
    );
  });
}
