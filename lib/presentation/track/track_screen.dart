import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../data/test_data/test_region.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/enums/track_source.dart';
import '../../map_rendering/layers/hd_terrain_layer.dart';
import '../../services/nostr/amber_signer_service.dart';
import '../../services/nostr/track_share_service.dart';
import '../../services/security/database_key_manager.dart';
import '../../services/track_recorder.dart';

class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Traccia')),
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
        PolylineLayer(
          polylines: [
            if (recorder.points.length >= 2)
              Polyline(
                points: [for (final p in recorder.points) p.position],
                color: WildBitColors.ochre,
                strokeWidth: 4,
              ),
          ],
        ),
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
      text: 'Traccia del ${DateTime.now().day}/${DateTime.now().month}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salva traccia'),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final track = SavedTrack(
      name: name.trim().isEmpty ? 'Traccia WildBit' : name.trim(),
      createdAt: DateTime.now(),
      distanceMeters: recorder.distanceMeters,
      durationSeconds: recorder.elapsed.inSeconds,
      elevationGainMeters: recorder.elevationGainMeters,
      source: TrackSource.recorded,
      points: List.unmodifiable(recorder.points),
    );
    final id = await recorder.stopAndSave(name: track.name);
    if (id != null && context.mounted) _shareDialog(context, track);
  }

  void _shareDialog(BuildContext context, SavedTrack track) {
    var publishing = false;
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
                    ),
                    children: [
                      const HdTerrainLayer(
                        features: MapFeatureCollection(
                          areas: [],
                          lines: [],
                          pois: [],
                        ),
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [for (final p in track.points) p.position],
                            color: WildBitColors.ochre,
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(track.distanceMeters / 1000).toStringAsFixed(2)} km · ${_formatDuration(Duration(seconds: track.durationSeconds))} · passo ${_pace(track)}',
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
                        if (context.mounted) Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Percorso pubblicato su Nostr.'),
                          ),
                        );
                      } catch (e) {
                        if (context.mounted)
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

  String _pace(SavedTrack track) => track.distanceMeters <= 0
      ? '—'
      : '${(track.durationSeconds * 1000 / track.distanceMeters ~/ 60)} min/km';

  @override
  Widget build(BuildContext context) {
    final distanceKm = (recorder.distanceMeters / 1000).toStringAsFixed(2);
    final speedKmh = (recorder.currentSpeedMetersPerSecond * 3.6)
        .toStringAsFixed(1);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _StatTile(label: 'Distanza', value: '$distanceKm km'),
                _StatTile(
                  label: 'Tempo',
                  value: _formatDuration(recorder.elapsed),
                ),
                _StatTile(label: 'Velocità', value: '$speedKmh km/h'),
                _StatTile(
                  label: 'Dislivello+',
                  value: '${recorder.elevationGainMeters.toStringAsFixed(0)} m',
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
        label: const Text('Inizia registrazione'),
      ),
      RecorderState.recording => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: recorder.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pausa'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ],
      ),
      RecorderState.paused => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: recorder.resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Riprendi'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
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
