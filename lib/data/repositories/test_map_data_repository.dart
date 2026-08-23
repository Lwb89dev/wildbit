import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/repositories/map_data_repository.dart';
import '../test_data/test_region.dart';

/// Phase 1 data source: a single hand-authored region, returned regardless
/// of the requested bounds. Swapped for an OSM-backed repository later
/// without touching rendering or presentation code.
class TestMapDataRepository implements MapDataRepository {
  @override
  Future<MapFeatureCollection> loadFeatures(GeoBounds bounds) async {
    return testRegionFeatures;
  }
}
