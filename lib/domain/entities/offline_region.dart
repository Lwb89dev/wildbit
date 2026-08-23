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
    this.completedAt,
  });

  final int? id;
  final String name;
  final GeoBounds bounds;
  final OfflineAreaStatus status;
  final double progress;
  final DateTime requestedAt;
  final DateTime? completedAt;

  OfflineRegion copyWith({
    int? id,
    OfflineAreaStatus? status,
    double? progress,
    DateTime? completedAt,
  }) {
    return OfflineRegion(
      id: id ?? this.id,
      name: name,
      bounds: bounds,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      requestedAt: requestedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
