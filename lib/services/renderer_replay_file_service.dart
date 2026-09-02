import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../map_rendering/performance/renderer_replay_bundle.dart';

/// Stores developer renderer replays locally for later ADB extraction.
///
/// This service neither uploads nor shares a map snapshot. The caller decides
/// whether a debug/profile build should expose the resulting local path.
class RendererReplayFileService {
  /// Checks the file length before materialising JSON in the Dart heap.
  Future<RendererReplayBundle> load(File file) async {
    if (await file.length() > RendererReplayBundle.maxEncodedBytes) {
      throw const FormatException('Il replay renderer supera 20 MB');
    }
    // JSON parsing and feature-cache restoration can be expensive on a dense
    // city/forest cell. Keep it off the map's UI isolate just like the normal
    // cache and Overpass parser paths.
    return compute(_decodeReplayBundle, await file.readAsString());
  }

  Future<File> save(RendererReplayBundle bundle) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'renderer_replays'));
    await directory.create(recursive: true);
    final timestamp = bundle.capturedAt.toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File(
      p.join(
        directory.path,
        'wildbit_renderer_$timestamp.${RendererReplayBundle.fileExtension}',
      ),
    );
    // Encoding may traverse thousands of OSM vertices and POIs. It is a
    // debug/profile operation, but still must not make the active map hitch.
    await file.writeAsString(
      await compute(_encodeReplayBundle, bundle),
      flush: true,
    );
    return file;
  }
}

RendererReplayBundle _decodeReplayBundle(String encoded) =>
    RendererReplayBundle.decode(encoded);

String _encodeReplayBundle(RendererReplayBundle bundle) => bundle.encode();
