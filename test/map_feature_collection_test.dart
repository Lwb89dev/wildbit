import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/domain/entities/area_feature.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';

void main() {
  test('deduplicates only features with the same explicit OSM identity', () {
    final collection = MapFeatureCollection(
      areas: const [
        AreaFeature(kind: MapFeatureKind.forest, ring: [], sourceId: '1'),
        AreaFeature(kind: MapFeatureKind.forest, ring: [], sourceId: '1'),
        AreaFeature(kind: MapFeatureKind.forest, ring: []),
      ],
      lines: const [
        LineFeature(
          kind: MapFeatureKind.trail,
          points: [],
          metadata: RouteMetadata(osmWayId: '2'),
        ),
        LineFeature(
          kind: MapFeatureKind.trail,
          points: [],
          metadata: RouteMetadata(osmWayId: '2'),
        ),
      ],
      pois: const [],
    ).deduplicated();

    expect(collection.areas, hasLength(2));
    expect(collection.lines, hasLength(1));
  });
}
