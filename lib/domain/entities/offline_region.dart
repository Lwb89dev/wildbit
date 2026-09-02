import '../enums/offline_area_status.dart';
import 'geo_bounds.dart';

class OfflineRegion {
  const OfflineRegion({
    this.id,
    required this.name,
    required this.bounds,
    required this.status,
    required this.progress,
    required this.requestedAt,
    this.minZoom = 12,
    this.maxZoom = 15,
    this.retryCount = 0,
    this.lastError,
    this.completedAt,
  });

  final int? id;
  final String name;
  final GeoBounds bounds;
  final OfflineAreaStatus status;
  final double progress;
  final DateTime requestedAt;

  /// Exact raster/overlay zoom range selected by the user. Keeping it with
  /// the region makes a retry identical to the original download.
  final int minZoom;
  final int maxZoom;
  final int retryCount;
  final String? lastError;
  final DateTime? completedAt;

  OfflineRegion copyWith({
    int? id,
    OfflineAreaStatus? status,
    double? progress,
    DateTime? completedAt,
    int? retryCount,
    String? lastError,
  }) {
    return OfflineRegion(
      id: id ?? this.id,
      name: name,
      bounds: bounds,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      requestedAt: requestedAt,
      minZoom: minZoom,
      maxZoom: maxZoom,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
