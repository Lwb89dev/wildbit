import 'dart:math' as math;

import 'saved_track.dart';

/// Derived, presentation- and sharing-safe metrics for a completed track.
class TrackSummary {
  const TrackSummary({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  factory TrackSummary.fromTrack(SavedTrack track) {
    if (track.points.isEmpty) {
      return TrackSummary(
        distanceMeters: track.distanceMeters,
        durationSeconds: track.durationSeconds,
        elevationGainMeters: track.elevationGainMeters,
        south: null,
        west: null,
        north: null,
        east: null,
      );
    }
    var south = track.points.first.position.latitude;
    var north = south;
    var west = track.points.first.position.longitude;
    var east = west;
    for (final fix in track.points.skip(1)) {
      south = math.min(south, fix.position.latitude);
      north = math.max(north, fix.position.latitude);
      west = math.min(west, fix.position.longitude);
      east = math.max(east, fix.position.longitude);
    }
    return TrackSummary(
      distanceMeters: track.distanceMeters,
      durationSeconds: track.durationSeconds,
      elevationGainMeters: track.elevationGainMeters,
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }

  final double distanceMeters;
  final int durationSeconds;
  final double elevationGainMeters;
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  double? get averagePaceSecondsPerKm =>
      distanceMeters <= 0 ? null : durationSeconds * 1000 / distanceMeters;

  String get formattedPace {
    final pace = averagePaceSecondsPerKm;
    if (pace == null || !pace.isFinite) return '—';
    final totalSeconds = pace.round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')} min/km';
  }

  Map<String, num>? get boundingBox =>
      south == null || west == null || north == null || east == null
      ? null
      : {'south': south!, 'west': west!, 'north': north!, 'east': east!};
}
