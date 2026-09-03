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
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
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

/// A Nostr event that the user explicitly chose to publish, but that no relay
/// accepted while the device was offline. The containing database is encrypted
/// at rest, so the signed event (and its exact GPS track) is never placed in
/// preferences, logs or an unencrypted app file while it waits for a retry.
class PendingNostrPublications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
}
