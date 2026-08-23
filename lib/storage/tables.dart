import 'package:drift/drift.dart';

/// One recorded or imported hiking track (metadata only — the actual
/// points live in [TrackPoints]).
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  RealColumn get distanceMeters => real().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  RealColumn get elevationGainMeters => real().withDefault(const Constant(0))();
  // 'recorded' (live GPS session) or 'imported' (from a .gpx file).
  TextColumn get source => text()();
}

/// A single GPS fix belonging to a track, in insertion order.
class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitudeMeters => real().nullable()();
  IntColumn get timestampMs => integer()();
  RealColumn get accuracyMeters => real().nullable()();
  RealColumn get speedMetersPerSecond => real().nullable()();
  RealColumn get headingDegrees => real().nullable()();
}

/// Raw OSM-derived map features cached for a quantized bounding-box cell,
/// so the app keeps working offline once a region has been visited/downloaded.
class CachedMapCells extends Table {
  TextColumn get cellKey => text()();
  DateTimeColumn get fetchedAt => dateTime()();
  TextColumn get featuresJson => text()();

  @override
  Set<Column> get primaryKey => {cellKey};
}

/// A user-requested offline area and its download state.
class OfflineAreas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get southWestLat => real()();
  RealColumn get southWestLng => real()();
  RealColumn get northEastLat => real()();
  RealColumn get northEastLng => real()();
  // 'queued' | 'downloading' | 'completed' | 'failed'.
  TextColumn get status => text().withDefault(const Constant('queued'))();
  RealColumn get progress => real().withDefault(const Constant(0))();
  DateTimeColumn get requestedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}
