import '../enums/track_source.dart';
import 'geo_fix.dart';

/// A hiking track: either recorded live via GPS or imported from a GPX
/// file. [points] are stored fixes, in order.
class SavedTrack {
  const SavedTrack({
    this.id,
    required this.name,
    required this.createdAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    required this.source,
    required this.points,
  });

  final int? id;
  final String name;
  final DateTime createdAt;
  final double distanceMeters;
  final int durationSeconds;
  final double elevationGainMeters;
  final TrackSource source;
  final List<GeoFix> points;

  SavedTrack copyWith({int? id}) {
    return SavedTrack(
      id: id ?? this.id,
      name: name,
      createdAt: createdAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      elevationGainMeters: elevationGainMeters,
      source: source,
      points: points,
    );
  }
}
