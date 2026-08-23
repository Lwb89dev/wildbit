import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/entities/saved_track.dart';
import 'gpx_track_codec.dart';

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

    final file = File(path);
    if (await file.length() > _maxImportBytes) {
      throw const FormatException('Il file GPX supera la dimensione massima supportata (20 MB)');
    }
    final content = await file.readAsString();
    return GpxTrackCodec.decode(content, fallbackName: p.basenameWithoutExtension(path));
  }

  Future<void> exportAndShare(SavedTrack track) async {
    final xml = GpxTrackCodec.encode(track);
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${_sanitize(track.name)}.gpx';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(xml);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Traccia WildBit: ${track.name}'),
    );
  }

  String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '_').trim();
    return cleaned.isEmpty ? 'wildbit_track' : cleaned;
  }
}
