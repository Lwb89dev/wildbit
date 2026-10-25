import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/entities/saved_track.dart';
import 'gpx_track_codec.dart';

/// A GPX import the user can act on; [messageKey] is a localization key.
class GpxImportException implements Exception {
  const GpxImportException(this.messageKey);

  final String messageKey;

  @override
  String toString() => 'GpxImportException($messageKey)';
}

/// Ties [GpxTrackCodec] to the filesystem: picking a `.gpx` file to import,
/// and writing/sharing one on export.
class GpxFileService {
  /// A real hiking track's GPX file is a few hundred KB at most; this is a
  /// generous cap against an oversized (accidental or malicious) file
  /// exhausting memory when read fully into a String.
  static const _maxImportBytes = 20 * 1024 * 1024;

  Future<SavedTrack?> pickAndImport() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return null;

    try {
      final file = File(path);
      if (await file.length() > _maxImportBytes) {
        throw const GpxImportException('gpx.tooLarge');
      }
      final content = await file.readAsString();
      // XML parsing and the geodesic distance of a long recording would
      // stall the UI isolate for a large file.
      return await compute(_decodeGpx, (
        content,
        p.basenameWithoutExtension(path),
      ));
    } on FormatException {
      throw const GpxImportException('gpx.noTrack');
    } finally {
      // The picker copies the chosen file into the app cache; do not leave a
      // plaintext copy of someone's track behind once it is imported.
      await _clearPickerCopies();
    }
  }

  Future<void> exportAndShare(
    SavedTrack track, {
    required String shareText,
  }) async {
    final xml = GpxTrackCodec.encode(track);
    // Stage the plaintext GPX in the cache directory, which Android never
    // backs up, and remove it as soon as the share sheet has its own copy:
    // exports used to accumulate unencrypted in the documents directory.
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, '${_sanitize(track.name)}.gpx'));
    await file.writeAsString(xml, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: shareText),
      );
    } finally {
      await _deleteQuietly(file);
    }
  }

  /// Removes GPX exports and database backups that earlier versions left
  /// unencrypted (GPX) or duplicated (backups) in the documents directory.
  static Future<void> removeLegacyExports() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final legacyGpx = name.toLowerCase().endsWith('.gpx');
        final legacyBackup =
            name.startsWith('wildbit_backup_') && name.endsWith('.sqlite');
        if (legacyGpx || legacyBackup) await _deleteQuietly(entity);
      }
    } catch (_) {
      // Housekeeping only (and no storage plugin in tests): the next launch
      // tries again.
    }
  }

  static Future<void> _clearPickerCopies() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Not every platform keeps (or can clear) picker copies.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file the platform still holds is removed on the next cleanup.
    }
  }

  String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '_').trim();
    return cleaned.isEmpty ? 'wildbit_track' : cleaned;
  }
}

SavedTrack _decodeGpx((String, String) input) =>
    GpxTrackCodec.decode(input.$1, fallbackName: input.$2);
