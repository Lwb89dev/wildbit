import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/saved_track.dart';
import '../../domain/enums/track_source.dart';
import '../../domain/repositories/track_repository.dart';
import '../../gpx/gpx_file_service.dart';
import 'track_detail_screen.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _gpxFileService = GpxFileService();
  late Future<List<SavedTrack>> _tracksFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _tracksFuture = context.read<TrackRepository>().listTracks();
  }

  Future<void> _importGpx() async {
    try {
      final imported = await _gpxFileService.pickAndImport();
      if (imported == null || !mounted) return;
      await context.read<TrackRepository>().saveTrack(imported);
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile importare il file GPX: $e')),
      );
    }
  }

  Future<void> _delete(int id) async {
    await context.read<TrackRepository>().deleteTrack(id);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Percorsi'),
        actions: [
          IconButton(onPressed: _importGpx, icon: const Icon(Icons.file_upload), tooltip: 'Importa GPX'),
        ],
      ),
      body: FutureBuilder<List<SavedTrack>>(
        future: _tracksFuture,
        builder: (context, snapshot) {
          final tracks = snapshot.data;
          if (tracks == null) return const Center(child: CircularProgressIndicator());
          if (tracks.isEmpty) return const _EmptyState();

          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) => _TrackTile(
              track: tracks[index],
              onDelete: () => _delete(tracks[index].id!),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text(
              'Nessun percorso ancora.\nRegistra una traccia o importa un file GPX.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onDelete});

  final SavedTrack track;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final km = (track.distanceMeters / 1000).toStringAsFixed(2);
    final isImported = track.source == TrackSource.imported;

    return ListTile(
      leading: Icon(isImported ? Icons.file_present : Icons.fiber_manual_record),
      title: Text(track.name),
      subtitle: Text('$km km · ${(track.durationSeconds / 60).round()} min'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TrackDetailScreen(trackId: track.id!)),
      ),
      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
    );
  }
}
