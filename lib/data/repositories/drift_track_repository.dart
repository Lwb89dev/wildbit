import 'package:drift/drift.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/geo_fix.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/enums/track_source.dart';
import '../../domain/repositories/track_repository.dart';
import '../../storage/database.dart';

class DriftTrackRepository implements TrackRepository {
  DriftTrackRepository(this._database);

  final WildBitDatabase _database;

  @override
  Future<int> saveTrack(SavedTrack track) {
    return _database.transaction(() async {
      final id = track.id == null
          ? await _database.into(_database.tracks).insert(_toTracksCompanion(track))
          : await _replaceTrack(track.id!, track);

      await (_database.delete(_database.trackPoints)..where((t) => t.trackId.equals(id))).go();
      await _database.batch((batch) {
        batch.insertAll(_database.trackPoints, [
          for (final (index, point) in track.points.indexed)
            TrackPointsCompanion.insert(
              trackId: id,
              sequence: index,
              latitude: point.position.latitude,
              longitude: point.position.longitude,
              altitudeMeters: Value(point.altitudeMeters),
              timestampMs: point.timestamp.millisecondsSinceEpoch,
              accuracyMeters: Value(point.accuracyMeters),
              speedMetersPerSecond: Value(point.speedMetersPerSecond),
              headingDegrees: Value(point.headingDegrees),
            ),
        ]);
      });
      return id;
    });
  }

  Future<int> _replaceTrack(int id, SavedTrack track) async {
    await (_database.update(_database.tracks)..where((t) => t.id.equals(id)))
        .write(_toTracksCompanion(track));
    return id;
  }

  TracksCompanion _toTracksCompanion(SavedTrack track) {
    return TracksCompanion.insert(
      name: track.name,
      createdAt: track.createdAt,
      distanceMeters: Value(track.distanceMeters),
      durationSeconds: Value(track.durationSeconds),
      elevationGainMeters: Value(track.elevationGainMeters),
      source: track.source.name,
    );
  }

  @override
  Future<List<SavedTrack>> listTracks() async {
    final rows = await (_database.select(_database.tracks)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return [for (final row in rows) _toSavedTrack(row, const [])];
  }

  @override
  Future<SavedTrack?> getTrack(int id) async {
    final row =
        await (_database.select(_database.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;

    final pointRows = await (_database.select(_database.trackPoints)
          ..where((t) => t.trackId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();

    return _toSavedTrack(row, pointRows);
  }

  @override
  Future<void> deleteTrack(int id) async {
    await (_database.delete(_database.tracks)..where((t) => t.id.equals(id))).go();
  }

  SavedTrack _toSavedTrack(Track row, List<TrackPoint> pointRows) {
    return SavedTrack(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      distanceMeters: row.distanceMeters,
      durationSeconds: row.durationSeconds,
      elevationGainMeters: row.elevationGainMeters,
      source: TrackSource.values.byName(row.source),
      points: [
        for (final p in pointRows)
          GeoFix(
            position: LatLng(p.latitude, p.longitude),
            timestamp: DateTime.fromMillisecondsSinceEpoch(p.timestampMs),
            altitudeMeters: p.altitudeMeters,
            accuracyMeters: p.accuracyMeters,
            speedMetersPerSecond: p.speedMetersPerSecond,
            headingDegrees: p.headingDegrees,
          ),
      ],
    );
  }
}
