import 'package:drift/drift.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/offline_region.dart';
import '../../domain/enums/offline_area_status.dart';
import '../../domain/repositories/offline_region_repository.dart';
import '../../storage/database.dart';

class DriftOfflineRegionRepository implements OfflineRegionRepository {
  DriftOfflineRegionRepository(this._database);

  final WildBitDatabase _database;

  @override
  Future<int> create(OfflineRegion area) {
    return _database.into(_database.offlineAreas).insert(
          OfflineAreasCompanion.insert(
            name: area.name,
            southWestLat: area.bounds.southWest.latitude,
            southWestLng: area.bounds.southWest.longitude,
            northEastLat: area.bounds.northEast.latitude,
            northEastLng: area.bounds.northEast.longitude,
            status: Value(area.status.name),
            progress: Value(area.progress),
            requestedAt: area.requestedAt,
          ),
        );
  }

  @override
  Future<void> updateStatus(int id, {required OfflineAreaStatus status, double? progress}) async {
    await (_database.update(_database.offlineAreas)..where((t) => t.id.equals(id))).write(
      OfflineAreasCompanion(
        status: Value(status.name),
        progress: progress == null ? const Value.absent() : Value(progress),
        completedAt: status == OfflineAreaStatus.completed ? Value(DateTime.now()) : const Value.absent(),
      ),
    );
  }

  @override
  Future<List<OfflineRegion>> listAreas() async {
    final rows = await (_database.select(_database.offlineAreas)
          ..orderBy([(t) => OrderingTerm.desc(t.requestedAt)]))
        .get();
    return [
      for (final row in rows)
        OfflineRegion(
          id: row.id,
          name: row.name,
          bounds: GeoBounds(
            southWest: LatLng(row.southWestLat, row.southWestLng),
            northEast: LatLng(row.northEastLat, row.northEastLng),
          ),
          status: OfflineAreaStatus.values.byName(row.status),
          progress: row.progress,
          requestedAt: row.requestedAt,
          completedAt: row.completedAt,
        ),
    ];
  }

  @override
  Future<void> deleteArea(int id) async {
    await (_database.delete(_database.offlineAreas)..where((t) => t.id.equals(id))).go();
  }
}
