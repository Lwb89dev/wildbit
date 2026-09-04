import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../data/test_data/test_region.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/saved_track.dart';
import '../../domain/repositories/track_repository.dart';
import '../../gpx/gpx_file_service.dart';
import '../../map_rendering/layers/hd_terrain_layer.dart';
import '../track/track_share_dialog.dart';
import '../../app/localization/app_localizations.dart';

class TrackDetailScreen extends StatefulWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final int trackId;

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  final _gpxFileService = GpxFileService();
  late final Future<SavedTrack?> _trackFuture = context
      .read<TrackRepository>()
      .getTrack(widget.trackId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SavedTrack?>(
      future: _trackFuture,
      builder: (context, snapshot) {
        final track = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(track?.name ?? '...'),
            actions: [
              if (track != null) ...[
                IconButton(
                  tooltip: context.l10n.text('share.title'),
                  icon: const Icon(Icons.public),
                  onPressed: () => showTrackShareDialog(context, track),
                ),
                IconButton(
                  tooltip: context.l10n.text('routes.export'),
                  icon: const Icon(Icons.share),
                  onPressed: () => _gpxFileService.exportAndShare(track),
                ),
              ],
            ],
          ),
          body: track == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: track.points.isNotEmpty
                        ? track.points.first.position
                        : testRegionCenter,
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
        );
      },
    );
  }
}
