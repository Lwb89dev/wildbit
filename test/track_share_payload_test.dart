import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/geo_fix.dart';
import 'package:wildbit/domain/entities/saved_track.dart';
import 'package:wildbit/domain/entities/track_summary.dart';
import 'package:wildbit/domain/enums/track_source.dart';
import 'package:wildbit/services/nostr/track_share_payload.dart';

void main() {
  final track = SavedTrack(
    name: 'Anello del lago',
    createdAt: DateTime.utc(2026, 1, 1),
    distanceMeters: 1500,
    durationSeconds: 390,
    elevationGainMeters: 84,
    source: TrackSource.recorded,
    points: [
      GeoFix(
        position: const LatLng(46, 11),
        timestamp: DateTime.utc(2026, 1, 1),
      ),
      GeoFix(
        position: const LatLng(46.001, 11.002),
        timestamp: DateTime.utc(2026, 1, 1, 0, 6, 30),
      ),
    ],
  );

  test('formats average pace as minutes and seconds per kilometre', () {
    expect(TrackSummary.fromTrack(track).formattedPace, '04:20 min/km');
  });

  test('creates a versioned public payload with geographic bounds', () {
    final payload = TrackSharePayload.fromTrack(track);
    expect(payload['type'], 'wildbit_hike');
    expect(payload['version'], 1);
    expect(payload['elevation_gain_m'], 84);
    expect(payload['average_pace_s_per_km'], 260);
    expect(payload['bbox'], {
      'south': 46.0,
      'west': 11.0,
      'north': 46.001,
      'east': 11.002,
    });
    expect((payload['track'] as List), hasLength(2));
  });
}
