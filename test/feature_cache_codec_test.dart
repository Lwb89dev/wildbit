import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/osm/feature_cache_codec.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/hiking_route_membership.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/entities/poi.dart';
import 'package:wildbit/domain/entities/poi_metadata.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';

void main() {
  test('persists ordered OSM node references for topology', () {
    final source = MapFeatureCollection(
      areas: const [],
      pois: const [],
      lines: [
        LineFeature(
          kind: MapFeatureKind.trail,
          points: const [LatLng(46, 11), LatLng(46.001, 11.001)],
          nodeIds: const ['1', '2'],
          metadata: const RouteMetadata(
            osmWayId: '1',
            ref: '105',
            highwayTag: 'path',
            trackType: 'grade3',
            waterwayTag: 'river',
            flowDirection: 'backward',
            fordTag: 'yes',
            accessConditional: 'no @ (winter)',
            openingHours: 'May-Oct',
            hikingRoutes: [
              HikingRouteMembership(
                relationId: '700',
                ref: 'E5',
                name: 'Sentiero Europeo E5',
                network: 'nwn',
              ),
            ],
          ),
        ),
      ],
    );

    final restored = FeatureCacheCodec.decode(FeatureCacheCodec.encode(source));

    expect(restored.lines.single.nodeIds, ['1', '2']);
    expect(restored.lines.single.metadata.ref, '105');
    expect(restored.lines.single.metadata.highwayTag, 'path');
    expect(restored.lines.single.metadata.trackType, 'grade3');
    expect(restored.lines.single.metadata.waterwayTag, 'river');
    expect(restored.lines.single.metadata.flowDirection, 'backward');
    expect(restored.lines.single.metadata.fordTag, 'yes');
    expect(restored.lines.single.metadata.accessConditional, 'no @ (winter)');
    expect(restored.lines.single.metadata.openingHours, 'May-Oct');
    final route = restored.lines.single.metadata.hikingRoutes.single;
    expect(route.relationId, '700');
    expect(route.ref, 'E5');
    expect(route.name, 'Sentiero Europeo E5');
    expect(route.network, 'nwn');
  });

  test('persists OSM identities for filled polygons', () {
    const json =
        '{"areas":[{"kind":"water","ring":[[46,11],[46.1,11.1]],"sourceId":"77"}],"lines":[],"pois":[]}';

    expect(FeatureCacheCodec.decode(json).areas.single.sourceId, '77');
  });

  test('marks caches without a format version as stale', () {
    expect(FeatureCacheCodec.isCurrentFormat('{"areas":[]}'), isFalse);
    expect(
      FeatureCacheCodec.isCurrentFormat(
        FeatureCacheCodec.encode(
          const MapFeatureCollection(areas: [], lines: [], pois: []),
        ),
      ),
      isTrue,
    );
    expect(
      FeatureCacheCodec.isCurrentFormat(
        '  { "formatVersion" : ${FeatureCacheCodec.currentFormatVersion}, '
        '"areas": [] }',
      ),
      isTrue,
    );
  });

  test('persists completed optional queries even when they found nothing', () {
    const source = MapFeatureCollection(areas: [], lines: [], pois: []);
    final encoded = FeatureCacheCodec.encode(
      source,
      includesBuildings: true,
      includesIndividualTrees: true,
    );

    final entry = FeatureCacheCodec.decodeEntry(encoded);

    expect(entry.features.areas, isEmpty);
    expect(entry.includesBuildings, isTrue);
    expect(entry.includesIndividualTrees, isTrue);
  });

  test('persists safety-relevant POI metadata', () {
    const source = MapFeatureCollection(
      areas: [],
      lines: [],
      pois: [
        Poi(
          id: 'osm-node-42',
          name: 'Fonte',
          type: PoiType.waterSource,
          position: LatLng(46, 11),
          metadata: PoiMetadata(
            elevationMeters: 1234,
            access: 'permissive',
            drinkingWater: false,
            operatorName: 'Comune',
            openingHours: '24/7',
          ),
        ),
      ],
    );

    final restored = FeatureCacheCodec.decode(FeatureCacheCodec.encode(source));
    final metadata = restored.pois.single.metadata;

    expect(metadata.elevationMeters, 1234);
    expect(metadata.access, 'permissive');
    expect(metadata.drinkingWater, isFalse);
    expect(metadata.operatorName, 'Comune');
    expect(metadata.openingHours, '24/7');
  });

  test('persists the shelter class used to select its silhouette', () {
    const source = MapFeatureCollection(
      areas: [],
      lines: [],
      pois: [
        Poi(
          id: 'osm-node-84',
          name: 'Bivacco',
          type: PoiType.shelter,
          position: LatLng(46, 11),
          metadata: PoiMetadata(shelterType: 'wilderness_hut'),
        ),
      ],
    );

    final restored = FeatureCacheCodec.decode(FeatureCacheCodec.encode(source));

    expect(restored.pois.single.metadata.shelterType, 'wilderness_hut');
  });
}
