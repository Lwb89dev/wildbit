import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_fix.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/entities/track_summary.dart';

/// Versioned content envelope for a WildBit hike note.
///
/// Keeping this separate from the relay/signing code makes the public format
/// deterministic and testable without network access.
abstract final class TrackSharePayload {
  /// Radius of the optional privacy zone around the start and the finish.
  static const privacyRadiusMeters = 200.0;

  /// Builds the public content. With [hideEndpoints], points within
  /// [privacyRadiusMeters] of the first and last fix are left out, so the
  /// published geometry does not lead to a home or a parked car. Distance,
  /// duration and pace still describe the whole hike.
  ///
  /// Throws a [StateError] when hiding the endpoints leaves fewer than two
  /// points to publish.
  static Map<String, dynamic> fromTrack(
    SavedTrack track, {
    bool hideEndpoints = false,
  }) {
    final summary = TrackSummary.fromTrack(track);
    final published = hideEndpoints
        ? withoutEndpointZones(track.points)
        : track.points;
    if (hideEndpoints && published.length < 2) {
      throw StateError('Too few points outside the privacy zones');
    }
    return {
      'type': 'wildbit_hike',
      'version': 1,
      'name': track.name,
      'source': track.source.name,
      'distance_m': summary.distanceMeters.round(),
      'duration_s': summary.durationSeconds,
      'elevation_gain_m': summary.elevationGainMeters.round(),
      'average_pace_s_per_km': summary.averagePaceSecondsPerKm?.round(),
      // Bounds of what is actually published: the whole track's bounds
      // would still reveal the hidden start and finish areas.
      'bbox': ?_bounds(published),
      'track': [
        for (final point in published)
          [
            point.position.latitude,
            point.position.longitude,
            point.timestamp.millisecondsSinceEpoch,
          ],
      ],
    };
  }

  /// The fixes left after trimming the start and finish zones: everything
  /// from the first fix that leaves the start zone to the last fix before
  /// the track enters the finish zone for good.
  static List<GeoFix> withoutEndpointZones(List<GeoFix> points) {
    if (points.length < 2) return const [];
    const distance = Distance();
    final start = points.first.position;
    final finish = points.last.position;
    var first = 0;
    while (first < points.length &&
        distance.as(LengthUnit.Meter, start, points[first].position) <=
            privacyRadiusMeters) {
      first++;
    }
    var last = points.length - 1;
    while (last >= first &&
        distance.as(LengthUnit.Meter, finish, points[last].position) <=
            privacyRadiusMeters) {
      last--;
    }
    if (first > last) return const [];
    return points.sublist(first, last + 1);
  }

  static Map<String, num>? _bounds(List<GeoFix> points) {
    if (points.isEmpty) return null;
    var south = points.first.position.latitude;
    var north = south;
    var west = points.first.position.longitude;
    var east = west;
    for (final point in points.skip(1)) {
      south = math.min(south, point.position.latitude);
      north = math.max(north, point.position.latitude);
      west = math.min(west, point.position.longitude);
      east = math.max(east, point.position.longitude);
    }
    return {'south': south, 'west': west, 'north': north, 'east': east};
  }
}
