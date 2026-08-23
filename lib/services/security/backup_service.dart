import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exports the (encrypted) local database file so the user can save or share
/// it themselves. The file on disk is already encrypted at rest — see
/// [DatabaseKeyManager] — so sharing it is safe even to an untrusted
/// destination; only the matching key (or, if linked, the matching nsec via
/// Amber) can ever decrypt it.
class BackupService {
  Future<void> exportAndShare() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dir.path, 'wildbit.sqlite'));
    if (!await dbFile.exists()) {
      throw StateError('Nessun database da esportare');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final exportFile = File(p.join(dir.path, 'wildbit_backup_$timestamp.sqlite'));
    await dbFile.copy(exportFile.path);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(exportFile.path)],
        text: 'Backup cifrato di WildBit ($timestamp)',
      ),
    );
  }
}
