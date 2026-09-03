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

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(pendingNostrPublications);
      }
      if (from < 5) {
        await migrator.deleteTable('offline_areas');
      }
    },
  );
}

LazyDatabase _openConnection(String encryptionKey) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'wildbit.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) => db.execute("PRAGMA key = \"x'$encryptionKey'\";"),
    );
  });
}
