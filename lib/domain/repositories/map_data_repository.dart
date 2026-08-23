import '../entities/geo_bounds.dart';
import '../entities/map_feature_collection.dart';

/// Abstraction over "where map data comes from". Phase 1 ships a
/// [TestMapDataRepository]; a later phase adds an OSM-backed
/// implementation (raw OSM data → processing → these same entities)
/// without any rendering or presentation code needing to change.
abstract interface class MapDataRepository {
  Future<MapFeatureCollection> loadFeatures(GeoBounds bounds);
}
