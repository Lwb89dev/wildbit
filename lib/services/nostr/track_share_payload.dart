import '../../domain/entities/saved_track.dart';
import '../../domain/entities/track_summary.dart';

/// Versioned content envelope for a WildBit hike note.
///
/// Keeping this separate from the relay/signing code makes the public format
/// deterministic and testable without network access.
abstract final class TrackSharePayload {
  static Map<String, dynamic> fromTrack(SavedTrack track) {
    final summary = TrackSummary.fromTrack(track);
    return {
      'type': 'wildbit_hike',
      'version': 1,
      'name': track.name,
      'source': track.source.name,
      'distance_m': summary.distanceMeters.round(),
      'duration_s': summary.durationSeconds,
      'elevation_gain_m': summary.elevationGainMeters.round(),
      'average_pace_s_per_km': summary.averagePaceSecondsPerKm?.round(),
      if (summary.boundingBox != null) 'bbox': summary.boundingBox,
      'track': [
        for (final point in track.points)
          [
            point.position.latitude,
            point.position.longitude,
            point.timestamp.millisecondsSinceEpoch,
          ],
      ],
    };
  }
}
