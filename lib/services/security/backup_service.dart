import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../storage/database.dart';

/// Thrown when there is no database file to export yet.
class BackupUnavailableException implements Exception {
  const BackupUnavailableException();
}

/// Exports the (encrypted) local database file so the user can save or share
/// it themselves. The file on disk is already encrypted at rest — see
/// [DatabaseKeyManager] — so sharing it is safe even to an untrusted
/// destination; only the matching key (or, if linked, the matching nsec via
/// Amber) can ever decrypt it.
class BackupService {
  /// [shareText] is the localized message that accompanies the file; it may
  /// contain a `{timestamp}` placeholder.
  Future<void> exportAndShare(
    WildBitDatabase database, {
    required String shareText,
  }) async {
    final dbFile = await WildBitDatabaseFile.location();
    if (!await dbFile.exists()) throw const BackupUnavailableException();

    final timestamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    // Stage the copy in the cache directory, which Android never backs up,
    // and delete it once the share sheet has taken its own copy. Copies in
    // the documents directory used to accumulate (and be cloud-backed-up).
    final staging = await getTemporaryDirectory();
    final exportFile = File(
      p.join(staging.path, 'wildbit_backup_$timestamp.sqlite'),
    );
    // Flush WAL pages first, then hold Drift's write transaction while the
    // filesystem snapshot is copied. Otherwise an active map-cache write can
    // leave the shared main file behind its WAL or change it mid-copy.
    await database.customStatement('PRAGMA wal_checkpoint(FULL)');
    await database.transaction(() => dbFile.copy(exportFile.path));

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(exportFile.path)],
          text: shareText.replaceAll('{timestamp}', timestamp),
        ),
      );
    } finally {
      try {
        if (await exportFile.exists()) await exportFile.delete();
      } on FileSystemException {
        // Cache files are reclaimed by the system if the delete races.
      }
    }
  }
}
