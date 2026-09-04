import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/entities/track_summary.dart';
import '../../map_rendering/layers/hd_terrain_layer.dart';
import '../../map_rendering/layers/pixel_recorded_track_layer.dart';
import '../../services/nostr/track_share_service.dart';
import '../../app/localization/app_localizations.dart';

/// Nostr sharing dialog shared by the just-recorded track flow
/// ([TrackScreen]) and the saved/archived track flow ([TrackDetailScreen]),
/// so both offer the same consent copy and publish behaviour.
void showTrackShareDialog(BuildContext context, SavedTrack track) {
  var publishing = false;
  var exactTrackConsent = false;
  final summary = TrackSummary.fromTrack(track);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.text('share.title')),
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
                context.l10n.shareSummary(
                  context.l10n.decimal(
                    summary.distanceMeters / 1000,
                    digits: 2,
                  ),
                  _formatDuration(Duration(seconds: summary.durationSeconds)),
                  summary.formattedPace,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.text('share.exactWarning'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: exactTrackConsent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(
                  context.l10n.text('share.consent'),
                  style: TextStyle(fontSize: 13),
                ),
                onChanged: publishing
                    ? null
                    : (value) => setDialogState(
                        () => exactTrackConsent = value ?? false,
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: publishing ? null : () => Navigator.pop(dialogContext),
            child: Text(context.l10n.text('share.dontShare')),
          ),
          FilledButton.icon(
            onPressed: publishing || !exactTrackConsent
                ? null
                : () async {
                    setDialogState(() => publishing = true);
                    try {
                      final result = await context
                          .read<TrackShareService>()
                          .publish(track);
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.queued
                                ? context.l10n.text('share.queued')
                                : context.l10n.text('share.published'),
                          ),
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
            label: Text(
              publishing
                  ? context.l10n.text('share.publishing')
                  : context.l10n.text('share.publish'),
            ),
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
