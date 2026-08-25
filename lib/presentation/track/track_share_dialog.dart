import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/entities/track_summary.dart';
import '../../map_rendering/layers/hd_terrain_layer.dart';
import '../../map_rendering/layers/pixel_recorded_track_layer.dart';
import '../../services/nostr/amber_signer_service.dart';
import '../../services/nostr/track_share_service.dart';
import '../../services/security/database_key_manager.dart';

/// Nostr sharing dialog shared by the just-recorded track flow
/// ([TrackScreen]) and the saved/archived track flow ([TrackDetailScreen]),
/// so both offer the same consent copy and publish behaviour.
void showTrackShareDialog(BuildContext context, SavedTrack track) {
  var publishing = false;
  final summary = TrackSummary.fromTrack(track);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Condividi su Nostr'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 150,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: track.points.first.position,
                    initialZoom: 14,
                    initialCameraFit: track.points.length < 2
                        ? null
                        : CameraFit.coordinates(
                            coordinates: [
                              for (final point in track.points) point.position,
                            ],
                            padding: const EdgeInsets.all(18),
                            maxZoom: 16,
                          ),
                  ),
                  children: [
                    const HdTerrainLayer(
                      features: MapFeatureCollection(
                        areas: [],
                        lines: [],
                        pois: [],
                      ),
                    ),
                    PixelRecordedTrackLayer(points: track.points),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(summary.distanceMeters / 1000).toStringAsFixed(2)} km · '
                '${_formatDuration(Duration(seconds: summary.durationSeconds))} · '
                'passo ${summary.formattedPace}',
              ),
              const SizedBox(height: 8),
              const Text(
                'La traccia GPS esatta sarà pubblica sui relay Nostr.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: publishing ? null : () => Navigator.pop(dialogContext),
            child: const Text('Non condividere'),
          ),
          FilledButton.icon(
            onPressed: publishing
                ? null
                : () async {
                    setDialogState(() => publishing = true);
                    try {
                      await TrackShareService(
                        keyManager: context.read<DatabaseKeyManager>(),
                        amber: context.read<AmberSignerService>(),
                      ).publish(track);
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Percorso pubblicato su Nostr.'),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                      setDialogState(() => publishing = false);
                    }
                  },
            icon: publishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.public),
            label: Text(publishing ? 'Pubblicazione…' : 'Pubblica'),
          ),
        ],
      ),
    ),
  );
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
