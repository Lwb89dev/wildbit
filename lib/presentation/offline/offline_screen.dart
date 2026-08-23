import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../data/test_data/test_region.dart';
import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/offline_region.dart';
import '../../domain/enums/offline_area_status.dart';
import '../../domain/repositories/offline_region_repository.dart';
import '../../location/location_service.dart';
import '../../offline/offline_download_manager.dart';

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  final _mapController = MapController();

  late Future<List<OfflineRegion>> _areasFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _areasFuture = context.read<OfflineRegionRepository>().listAreas();
  }

  Future<void> _downloadVisibleArea() async {
    final visible = _mapController.camera.visibleBounds;
    final bounds = GeoBounds(
      southWest: LatLng(visible.south, visible.west),
      northEast: LatLng(visible.north, visible.east),
    );

    final manager = context.read<OfflineDownloadManager>();
    await manager.requestDownload(
      name:
          'Area visibile ${visible.center.latitude.toStringAsFixed(2)}, ${visible.center.longitude.toStringAsFixed(2)}',
      bounds: bounds,
    );
    setState(_reload);
    // Refresh again shortly after so in-progress downloads show live status.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(_reload);
    });
  }

  Future<void> _delete(int id) async {
    await context.read<OfflineRegionRepository>().deleteArea(id);
    setState(_reload);
  }

  Future<void> _retry(OfflineRegion area) async {
    await context.read<OfflineDownloadManager>().retry(area);
    setState(_reload);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(_reload);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: testRegionCenter,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.wildbit.wildbit',
                      ),
                      // Public Waymarked Trails overlay: unlike the base map,
                      // this highlights the hiking network the user is about
                      // to cache for the selected viewport.
                      TileLayer(
                        urlTemplate:
                            'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.wildbit.wildbit',
                      ),
                    ],
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.crop_free,
                        size: 88,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 10,
                    child: Text(
                      'Sposta e zooma: l’overlay mostra i sentieri da scaricare nell’area visibile.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<OfflineRegion>>(
                future: _areasFuture,
                builder: (context, snapshot) {
                  final areas = snapshot.data;
                  if (areas == null)
                    return const Center(child: CircularProgressIndicator());
                  if (areas.isEmpty) return const _EmptyState();

                  return ListView.builder(
                    itemCount: areas.length,
                    itemBuilder: (context, index) => _AreaTile(
                      area: areas[index],
                      onDelete: () => _delete(areas[index].id!),
                      onRetry: () => _retry(areas[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _downloadVisibleArea,
        icon: const Icon(Icons.download),
        label: const Text('Scarica area visibile'),
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
            Icon(
              Icons.download_for_offline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nessuna area scaricata.\nSposta e zooma la mappa, poi scarica l’area visibile.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.area,
    required this.onDelete,
    required this.onRetry,
  });

  final OfflineRegion area;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(area.status), color: _colorFor(area.status)),
      title: Text(area.name),
      subtitle: area.status == OfflineAreaStatus.downloading
          ? LinearProgressIndicator(value: area.progress)
          : Text(_labelFor(area.status)),
      onTap: area.status == OfflineAreaStatus.failed ? onRetry : null,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }

  IconData _iconFor(OfflineAreaStatus status) => switch (status) {
    OfflineAreaStatus.queued => Icons.schedule,
    OfflineAreaStatus.downloading => Icons.downloading,
    OfflineAreaStatus.completed => Icons.check_circle,
    OfflineAreaStatus.failed => Icons.error_outline,
  };

  Color _colorFor(OfflineAreaStatus status) => switch (status) {
    OfflineAreaStatus.completed => WildBitColors.forestGreen,
    OfflineAreaStatus.failed => Colors.redAccent,
    _ => WildBitColors.brown,
  };

  String _labelFor(OfflineAreaStatus status) => switch (status) {
    OfflineAreaStatus.queued => 'In coda',
    OfflineAreaStatus.downloading => 'Download in corso',
    OfflineAreaStatus.completed => 'Disponibile offline',
    OfflineAreaStatus.failed => 'Fallito — tocca per riprovare',
  };
}
