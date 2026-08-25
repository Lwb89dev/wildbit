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
import '../../offline/offline_tile_cache.dart';
import '../../offline/offline_tile_plan.dart';
import '../../offline/offline_tile_provider.dart';
import '../../offline/offline_region_package.dart';
import '../../offline/offline_storage_service.dart';

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  final _mapController = MapController();
  LatLng _center = testRegionCenter;
  bool _locating = true;
  final _tileCache = OfflineTileCache();
  final _storage = OfflineStorageService();
  String? _tileCacheDirectory;
  int? _availableBytes;
  int? _cacheBytes;
  bool _cleaningCache = false;

  late Future<List<OfflineRegion>> _areasFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    _centerOnLocation();
    _loadTileCacheDirectory();
    _loadAvailableStorage();
    _loadCacheBytes();
  }

  Future<void> _loadTileCacheDirectory() async {
    final directory = await _tileCache.rootDirectory;
    if (mounted) setState(() => _tileCacheDirectory = directory.path);
  }

  Future<void> _loadAvailableStorage() async {
    final bytes = await _storage.availableBytes();
    if (mounted) setState(() => _availableBytes = bytes);
  }

  Future<void> _loadCacheBytes() async {
    final bytes = await _tileCache.cacheBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _cleanupPartialCache() async {
    if (_cleaningCache) return;
    setState(() => _cleaningCache = true);
    final removed = await _tileCache.cleanupPartialFiles();
    await _loadCacheBytes();
    if (!mounted) return;
    setState(() => _cleaningCache = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'Nessun download interrotto da pulire'
              : 'Puliti ${_formatBytes(removed)} di file incompleti',
        ),
      ),
    );
  }

  Future<void> _centerOnLocation() async {
    try {
      if (!await widget.locationService.ensurePermission()) return;
      final fix = await widget.locationService.getCurrentPosition();
      if (fix == null || !mounted) return;
      setState(() => _center = fix.position);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(fix.position, 13);
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _reload() {
    _areasFuture = context.read<OfflineRegionRepository>().listAreas();
  }

  Future<void> _downloadVisibleArea() async {
    final visible = _mapController.camera.visibleBounds;
    final selectedZoom = _visibleTileZoom;
    final bounds = GeoBounds(
      southWest: LatLng(visible.south, visible.west),
      northEast: LatLng(visible.north, visible.east),
    );

    try {
      final tiles = OfflineTilePlan.estimate(
        bounds,
        minZoom: selectedZoom,
        maxZoom: selectedZoom,
      );
      final bytes = _tileCache.estimatedBytes(
        bounds,
        requestedMinZoom: selectedZoom,
        requestedMaxZoom: selectedZoom,
      );
      await _ensureSpace(bytes);
      if (!mounted) return;
      final manager = context.read<OfflineDownloadManager>();
      await manager.requestDownload(
        name:
            'Area visibile z$selectedZoom ${visible.center.latitude.toStringAsFixed(2)}, ${visible.center.longitude.toStringAsFixed(2)}',
        bounds: bounds,
        minZoom: selectedZoom,
        maxZoom: selectedZoom,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Download avviato: z$selectedZoom · $tiles tile × 2 overlay · ${_formatBytes(bytes)}',
            ),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
    setState(_reload);
    // Refresh again shortly after so in-progress downloads show live status.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(_reload);
    });
  }

  int get _visibleTileZoom => _mapController.camera.zoom.round().clamp(
    _tileCache.minZoom,
    _tileCache.maxZoom,
  );

  Future<void> _downloadLocalPackage() async {
    final package = OfflineRegionPackage.local(_center);
    try {
      await _ensureSpace(_tileCache.estimatedBytes(package.bounds));
      if (!mounted) return;
      await context.read<OfflineDownloadManager>().requestDownload(
        name: package.name,
        bounds: package.bounds,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${package.name} avviato')));
        setState(_reload);
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }

  Future<void> _ensureSpace(int requiredBytes) async {
    final available = await _storage.availableBytes();
    if (mounted && available != null) {
      setState(() => _availableBytes = available);
    }
    if (available != null && available < requiredBytes) {
      throw StateError(
        'Spazio insufficiente: servono ${_formatBytes(requiredBytes)}, '
        'disponibili ${_formatBytes(available)}',
      );
    }
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
    final storageLabel = _availableBytes == null
        ? ''
        : ' · ${_formatBytes(_availableBytes!)} liberi';
    final cacheLabel = _cacheBytes == null
        ? ''
        : ' · cache ${_formatBytes(_cacheBytes!)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline'),
        actions: [
          IconButton(
            tooltip: 'Pulisci download interrotti',
            onPressed: _cleaningCache ? null : _cleanupPartialCache,
            icon: _cleaningCache
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: 'Centra sul GPS',
            onPressed: _centerOnLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
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
                      initialCenter: _center,
                      initialZoom: 13,
                      minZoom: 11,
                      maxZoom: 16,
                      onPositionChanged: (_, _) {
                        if (mounted) setState(() {});
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.wildbit.wildbit',
                        tileProvider: _tileCacheDirectory == null
                            ? null
                            : OfflineTileProvider(
                                source: OfflineTileSource.osm,
                                cacheDirectory: _tileCacheDirectory!,
                              ),
                      ),
                      // Public Waymarked Trails overlay: unlike the base map,
                      // this highlights the hiking network the user is about
                      // to cache for the selected viewport.
                      TileLayer(
                        urlTemplate:
                            'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.wildbit.wildbit',
                        tileProvider: _tileCacheDirectory == null
                            ? null
                            : OfflineTileProvider(
                                source: OfflineTileSource.hiking,
                                cacheDirectory: _tileCacheDirectory!,
                              ),
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
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 10,
                    child: Text(
                      _locating
                          ? 'Ricerca GPS in corso…'
                          : 'Sposta e zooma: z$_visibleTileZoom · overlay sentieri$storageLabel$cacheLabel',
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
                  if (areas == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'offline-local-package',
            onPressed: _downloadLocalPackage,
            icon: const Icon(Icons.hiking),
            label: const Text('Pacchetto locale'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'offline-visible-area',
            onPressed: _downloadVisibleArea,
            icon: const Icon(Icons.download),
            label: const Text('Scarica area visibile'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
