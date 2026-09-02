import '../entities/offline_region.dart';
import '../enums/offline_area_status.dart';

abstract interface class OfflineRegionRepository {
  Future<int> create(OfflineRegion area);
  Future<void> updateStatus(
    int id, {
    required OfflineAreaStatus status,
    double? progress,
    int? retryCount,
    String? lastError,
  });
  Future<List<OfflineRegion>> listAreas();
  Future<void> deleteArea(int id);
}
