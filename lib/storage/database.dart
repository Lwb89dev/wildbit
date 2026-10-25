import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Tracks, TrackPoints, CachedMapCells, PendingNostrPublications],
)
class WildBitDatabase extends _$WildBitDatabase {
  /// [encryptionKey] must be a 64-character hex string (32 bytes) — see
  /// `DatabaseKeyManager`. The database file is genuinely encrypted at rest
  /// (via the SQLite3MultipleCiphers build configured in pubspec.yaml),
  /// with or without a linked Nostr identity.
  WildBitDatabase(String encryptionKey) : super(_openConnection(encryptionKey));
  WildBitDatabase.forTesting(super.executor);

  static final _keyFormat = RegExp(r'^[0-9a-f]{64}$');

  /// True for keys in the format `DatabaseKeyManager` generates. The key is
  /// interpolated into a `PRAGMA`, so nothing else may ever reach SQLite.
  static bool isValidKey(String key) => _keyFormat.hasMatch(key);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(pendingNostrPublications);
      }
      if (from < 5) {
        await migrator.deleteTable('offline_areas');
      }
      if (from < 6) {
        // Deleting a track relied on ON DELETE CASCADE while SQLite's
        // foreign keys were off, so the GPS points of every deleted track
        // stayed in the database (and in exported backups). Purge them.
        await customStatement(
          'DELETE FROM track_points '
          'WHERE track_id NOT IN (SELECT id FROM tracks)',
        );
      }
    },
    beforeOpen: (details) async {
      // SQLite leaves foreign keys off unless every connection enables them.
      await customStatement('PRAGMA foreign_keys = ON');
      // Opening a track used to scan every stored GPS point.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS track_points_by_track '
        'ON track_points (track_id, sequence)',
      );
    },
  );
}

LazyDatabase _openConnection(String encryptionKey) {
  if (!WildBitDatabase.isValidKey(encryptionKey)) {
    throw ArgumentError('The database key has an unexpected format.');
  }
  return LazyDatabase(() async {
    final file = await WildBitDatabaseFile.location();
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        db.execute("PRAGMA key = \"x'$encryptionKey'\";");
        // Deleted tracks must not survive in free pages, where a backup
        // export or anyone holding the key could still read them.
        db.execute('PRAGMA secure_delete = ON;');
      },
    );
  });
}

/// The on-disk location of the encrypted database.
abstract final class WildBitDatabaseFile {
  static const fileName = 'wildbit.sqlite';

  static Future<File> location() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// Moves an existing database aside when its key is gone for good (an
  /// Android backup restored without a recoverable key, or a Keystore that
  /// lost the entry). A fresh key could never open it, and leaving it in
  /// place would make every query fail. Nothing is deleted.
  static Future<void> archiveUnreadable() async {
    final file = await location();
    if (!await file.exists()) return;
    final suffix = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    for (final extension in const ['', '-journal', '-wal', '-shm']) {
      final part = File('${file.path}$extension');
      if (await part.exists()) {
        await part.rename('${file.path}.unreadable-$suffix$extension');
      }
    }
  }
}
