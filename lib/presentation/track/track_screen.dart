import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../data/test_data/test_region.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/enums/track_source.dart';
import '../../app/localization/app_localizations.dart';
import '../../map_rendering/layers/hd_terrain_layer.dart';
import '../../map_rendering/layers/pixel_recorded_track_layer.dart';
import '../../services/track_recorder.dart';
import '../../services/nostr/track_share_service.dart';
import 'track_share_dialog.dart';

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<TrackShareService>().retryQueued());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('track.title'))),
      body: Consumer<TrackRecorderController>(
        builder: (context, recorder, _) => Column(
          children: [
            Expanded(child: _LiveMap(recorder: recorder)),
            _StatsAndControls(recorder: recorder),
          ],
        ),
      ),
    );
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap({required this.recorder});

  final TrackRecorderController recorder;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: recorder.points.isNotEmpty
            ? recorder.points.last.position
            : testRegionCenter,
        initialZoom: 16,
      ),
      children: [
        const HdTerrainLayer(
          features: MapFeatureCollection(areas: [], lines: [], pois: []),
        ),
        PixelRecordedTrackLayer(points: recorder.points),
      ],
    );
  }
}

class _StatsAndControls extends StatelessWidget {
  const _StatsAndControls({required this.recorder});

  final TrackRecorderController recorder;

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _stopAndSave(BuildContext context) async {
    final nameController = TextEditingController(
      text: context.l10n.trackDefaultName(DateTime.now()),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('track.saveTitle')),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: Text(context.l10n.text('common.save')),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final track = SavedTrack(
      name: name.trim().isEmpty
          ? context.l10n.text('track.savedName')
          : name.trim(),
      createdAt: DateTime.now(),
      distanceMeters: recorder.distanceMeters,
      durationSeconds: recorder.elapsed.inSeconds,
      elevationGainMeters: recorder.elevationGainMeters,
      source: TrackSource.recorded,
      points: List.unmodifiable(recorder.points),
    );
    final id = await recorder.stopAndSave(name: track.name);
    if (id != null && context.mounted) {
      showTrackShareDialog(context, track.copyWith(id: id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = context.l10n.decimal(
      recorder.distanceMeters / 1000,
      digits: 2,
    );
    final speedKmh = context.l10n.decimal(
      recorder.currentSpeedMetersPerSecond * 3.6,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _StatTile(
                  label: context.l10n.text('track.distance'),
                  value: '$distanceKm km',
                ),
                _StatTile(
                  label: context.l10n.text('track.time'),
                  value: _formatDuration(recorder.elapsed),
                ),
                _StatTile(
                  label: context.l10n.text('track.speed'),
                  value: '$speedKmh km/h',
                ),
                _StatTile(
                  label: context.l10n.text('track.elevation'),
                  value:
                      '${context.l10n.decimal(recorder.elevationGainMeters, digits: 0)} m',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Controls(recorder: recorder, onStop: () => _stopAndSave(context)),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.recorder, required this.onStop});

  final TrackRecorderController recorder;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return switch (recorder.state) {
      RecorderState.idle => FilledButton.icon(
        onPressed: recorder.start,
        icon: const Icon(Icons.fiber_manual_record),
        label: Text(context.l10n.text('track.start')),
      ),
      RecorderState.recording => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: recorder.pause,
            icon: const Icon(Icons.pause),
            label: Text(context.l10n.text('track.pause')),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: Text(context.l10n.text('track.stop')),
          ),
        ],
      ),
      RecorderState.paused => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: recorder.resume,
            icon: const Icon(Icons.play_arrow),
            label: Text(context.l10n.text('track.resume')),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: Text(context.l10n.text('track.stop')),
          ),
        ],
      ),
    };
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
