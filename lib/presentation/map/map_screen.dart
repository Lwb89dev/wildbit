import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme/theme_provider.dart';
import '../../app/theme/wildbit_theme.dart';
import '../../data/repositories/osm_map_data_repository.dart';
import '../../data/test_data/test_region.dart';
import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/geo_fix.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/entities/poi.dart';
import '../../domain/enums/poi_type.dart';
import '../../domain/routing/route_topology_graph.dart';
import '../../location/location_service.dart';
import '../../map_rendering/bit/bit_animation_controller.dart';
import '../../map_rendering/bit/bit_map_layer.dart';
import '../../map_rendering/layers/osm_pixel_bridge_layer.dart';
import '../../map_rendering/layers/osm_pixel_biome_layer.dart';
import '../../map_rendering/layers/osm_pixel_coastline_layer.dart';
import '../../map_rendering/layers/osm_pixel_contour_layer.dart';
import '../../map_rendering/layers/osm_pixel_geology_layer.dart';
import '../../map_rendering/layers/osm_pixel_poi_layer.dart';
import '../../map_rendering/layers/osm_pixel_foreground_vegetation_layer.dart';
import '../../map_rendering/layers/osm_pixel_flower_layer.dart';
import '../../map_rendering/layers/osm_pixel_route_layer.dart';
import '../../map_rendering/layers/osm_pixel_tree_layer.dart';
import '../../map_rendering/layers/osm_pixel_urban_layer.dart';
import '../../map_rendering/layers/osm_pixel_water_layer.dart';
import '../../map_rendering/layers/osm_pixel_waterway_layer.dart';
import '../../map_rendering/layers/pixel_terrain_base_layer.dart';
import '../../map_rendering/layers/pixel_map_legend.dart';
import '../../map_rendering/layers/pixel_position_marker.dart';
import '../../map_rendering/composition/coastline_topology_composer.dart';
import '../../services/kokoro/wildbit_voice_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _bitLayerKey = GlobalKey<BitMapLayerState>();
  final _bitRenderedPosition = ValueNotifier<LatLng?>(null);
  late final _bitController = BitAnimationController();
  OsmMapDataRepository? _dataRepository;
  Timer? _fetchDebounce;
  int _featureRequestId = 0;
  LatLng? _lastGpsFeatureFetch;
  final List<GeoBounds> _loadedFeatureRegions = [];

  MapFeatureCollection _features = const MapFeatureCollection(
    areas: [],
    lines: [],
    pois: [],
  );
  CoastlineTopology _coastlineTopology = const CoastlineTopology(
    chains: [],
    issues: [],
  );
  bool _followUser = true;
  bool _isLoadingFeatures = false;
  String? _mapDataError;
  bool _usingLocalPreview = false;
  double _zoom = 16;
  GeoFix? _lastFix;

  bool _showTrails = true;
  bool _showRoads = true;
  bool _showPois = true;
  MapFeatureCollection? _visibleFeaturesCache;
  MapFeatureCollection? _visibleFeaturesSource;
  bool? _cachedShowTrails;
  bool? _cachedShowRoads;
  bool? _cachedShowPois;

  static const _poiAnnounceRadiusMeters = 150.0;
  static const _poiDistance = Distance();
  final _announcedPoiIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dataRepository != null) return;
    _dataRepository = context.read<OsmMapDataRepository>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchForCurrentViewport();
    });
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _bitRenderedPosition.dispose();
    super.dispose();
  }

  GeoBounds _padded(LatLngBounds bounds) {
    final latPad = (bounds.north - bounds.south) * 0.5;
    final lngPad = (bounds.east - bounds.west) * 0.5;
    return GeoBounds(
      southWest: LatLng(bounds.south - latPad, bounds.west - lngPad),
      northEast: LatLng(bounds.north + latPad, bounds.east + lngPad),
    );
  }

  Future<void> _fetchForCurrentViewport() async {
    final bounds = _padded(_mapController.camera.visibleBounds);
    await _fetchFeaturesIfNeeded(bounds);
  }

  Future<void> _fetchFeaturesIfNeeded(GeoBounds bounds) async {
    if (_loadedFeatureRegions.any((region) => region.containsBounds(bounds))) {
      return;
    }
    await _fetchFeatures(bounds);
  }

  /// Loads an area centred on a GPS fix instead of relying on the map camera.
  /// `MapController.move` is applied on the next frame, so reading
  /// `visibleBounds` in the same callback can still return the old viewport.
  /// This makes the first render around the user's actual position reliable.
  Future<void> _fetchForGpsPosition(LatLng position) {
    // At the initial hiking zoom this is slightly wider than a phone viewport.
    // Keeping it below one 0.02° cache-cell width means this fetch needs at
    // most four small Overpass requests instead of a slow 3×3 block.
    const latitudeRadius = 0.0065;
    final longitudeRadius =
        latitudeRadius /
        math
            .cos(position.latitude * math.pi / 180)
            .abs()
            .clamp(0.2, 1.0)
            .toDouble();
    return _fetchFeaturesIfNeeded(
      GeoBounds(
        southWest: LatLng(
          position.latitude - latitudeRadius,
          position.longitude - longitudeRadius,
        ),
        northEast: LatLng(
          position.latitude + latitudeRadius,
          position.longitude + longitudeRadius,
        ),
      ),
    );
  }

  Future<void> _fetchFeatures(GeoBounds bounds) async {
    final repository = _dataRepository;
    if (repository == null) return;
    final requestId = ++_featureRequestId;

    setState(() => _isLoadingFeatures = true);
    try {
      final features = await repository.loadFeatures(bounds);
      if (kDebugMode) {
        debugPrint(
          'WildBit OSM features: areas=${features.areas.length}, '
          'buildings=${features.areas.where((a) => a.kind == MapFeatureKind.building).length}, '
          'trees=${features.pois.where((p) => p.type == PoiType.tree).length}, '
          'lines=${features.lines.length}',
        );
      }
      if (!mounted || requestId != _featureRequestId) return;
      final hasNoFeatures =
          features.areas.isEmpty &&
          features.lines.isEmpty &&
          features.pois.isEmpty;
      final useLocalPreview =
          kDebugMode && hasNoFeatures && repository.lastLoadError != null;
      setState(() {
        _features = useLocalPreview
            ? testRegionFeatures
            : _mergeFeatures(features, _features);
        _coastlineTopology = CoastlineTopologyComposer.compose(
          _features.lines.where(
            (line) => line.kind == MapFeatureKind.coastline,
          ),
        );
        _loadedFeatureRegions.add(bounds);
        _isLoadingFeatures = false;
        _usingLocalPreview = useLocalPreview;
        _mapDataError = hasNoFeatures && repository.lastLoadError != null
            ? (useLocalPreview
                  ? 'Anteprima locale · OSM non disponibile'
                  : 'Dati mappa non disponibili')
            : null;
      });
    } catch (_) {
      if (mounted && requestId == _featureRequestId) {
        setState(() {
          _isLoadingFeatures = false;
          _usingLocalPreview = kDebugMode;
          _features = kDebugMode ? testRegionFeatures : _features;
          _coastlineTopology = CoastlineTopologyComposer.compose(
            _features.lines.where(
              (line) => line.kind == MapFeatureKind.coastline,
            ),
          );
          if (kDebugMode) _loadedFeatureRegions.add(bounds);
          _mapDataError = kDebugMode
              ? 'Anteprima locale · OSM non disponibile'
              : 'Dati mappa non disponibili';
        });
      }
    }
  }

  MapFeatureCollection _mergeFeatures(
    MapFeatureCollection newest,
    MapFeatureCollection existing,
  ) => MapFeatureCollection(
    // New data comes first so a refreshed OSM identity supersedes its
    // cached representation instead of preserving stale geometry.
    areas: [...newest.areas, ...existing.areas],
    lines: [...newest.lines, ...existing.lines],
    pois: [...newest.pois, ...existing.pois],
  ).deduplicated();

  void _scheduleFetch() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(
      const Duration(milliseconds: 600),
      _fetchForCurrentViewport,
    );
  }

  void _onPositionUpdate(GeoFix point) {
    _lastFix = point;
    context.read<ThemeProvider>().onPositionUpdate(
      point.position.latitude,
      point.position.longitude,
    );
    _checkPoiProximity(point);
    if (_followUser) {
      _mapController.move(point.position, _mapController.camera.zoom);
    }
    _loadFeaturesNearGpsPosition(point.position);
  }

  void _loadFeaturesNearGpsPosition(LatLng position) {
    final last = _lastGpsFeatureFetch;
    if (last != null &&
        _poiDistance.as(LengthUnit.Meter, last, position) < 150) {
      return;
    }
    _lastGpsFeatureFetch = position;
    _fetchDebounce?.cancel();
    unawaited(_fetchForGpsPosition(position));
  }

  void _checkPoiProximity(GeoFix point) {
    for (final poi in _features.pois) {
      if (_announcedPoiIds.contains(poi.id)) continue;
      final distance = _poiDistance.as(
        LengthUnit.Meter,
        point.position,
        poi.position,
      );
      if (distance > _poiAnnounceRadiusMeters) continue;
      _announcedPoiIds.add(poi.id);
      context.read<WildBitVoiceService>().announcePoiNearby(poi.name);
    }
  }

  Future<void> _centerOnUser() async {
    setState(() => _followUser = true);
    final freshFix = await widget.locationService.getCurrentPosition();
    if (!mounted) return;
    final position =
        freshFix?.position ??
        _bitLayerKey.currentState?.currentPosition ??
        _lastFix?.position;
    if (freshFix != null) {
      _lastFix = freshFix;
    }
    if (position != null) {
      _mapController.move(position, _mapController.camera.zoom);
      unawaited(_fetchForGpsPosition(position));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attiva la posizione per centrare la mappa.'),
      ),
    );
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + delta).clamp(3.0, 19.0);
    setState(() => _zoom = newZoom);
    _mapController.move(camera.center, newZoom);
    _fetchForCurrentViewport();
  }

  void _openLayersSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final topology = RouteTopologyBuilder.build(_visibleFeatures.lines);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Livelli mappa',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  CheckboxListTile(
                    value: _showTrails,
                    title: const Text('Sentieri'),
                    onChanged: (v) => setSheetState(
                      () => setState(() => _showTrails = v ?? true),
                    ),
                  ),
                  CheckboxListTile(
                    value: _showRoads,
                    title: const Text('Strade'),
                    onChanged: (v) => setSheetState(
                      () => setState(() => _showRoads = v ?? true),
                    ),
                  ),
                  CheckboxListTile(
                    value: _showPois,
                    title: const Text('Punti di interesse'),
                    onChanged: (v) => setSheetState(
                      () => setState(() => _showPois = v ?? true),
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Icon(
                        topology.excludedWayCount == 0
                            ? Icons.account_tree_outlined
                            : Icons.warning_amber_rounded,
                        color: topology.excludedWayCount == 0
                            ? WildBitColors.forestGreen
                            : WildBitColors.brown,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          topology.excludedWayCount == 0
                              ? '${topology.verifiedWayCount} vie con topologia OSM disponibile'
                              : '${topology.excludedWayCount} vie senza topologia verificabile',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La topologia verifica solo i nodi OSM: non equivale a un percorso sicuro o consigliato.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Debug OSM: ${_features.areas.where((a) => a.kind == MapFeatureKind.building).length} edifici · '
                      '${_features.pois.where((p) => p.type == PoiType.tree).length} alberi',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_dataRepository?.lastLoadError != null)
                      Text(
                        'Fetch OSM: ${_dataRepository!.lastLoadError}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openPoiDetails(Poi poi) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PoiDetailsSheet(
        poi: poi,
        onCenter: () {
          Navigator.of(sheetContext).pop();
          setState(() => _followUser = false);
          final targetZoom = math.max(_mapController.camera.zoom, 16.0);
          _mapController.move(poi.position, targetZoom);
          _scheduleFetch();
        },
      ),
    );
  }

  MapFeatureCollection get _visibleFeatures {
    if (identical(_visibleFeaturesSource, _features) &&
        _cachedShowTrails == _showTrails &&
        _cachedShowRoads == _showRoads &&
        _cachedShowPois == _showPois &&
        _visibleFeaturesCache != null) {
      return _visibleFeaturesCache!;
    }
    final scene = MapFeatureCollection(
      areas: _features.areas,
      lines: _features.lines.where((line) {
        if (line.kind == MapFeatureKind.trail) return _showTrails;
        if (line.kind == MapFeatureKind.road) return _showRoads;
        return true;
      }).toList(),
      pois: _showPois ? _features.pois : const [],
    );
    _visibleFeaturesSource = _features;
    _cachedShowTrails = _showTrails;
    _cachedShowRoads = _showRoads;
    _cachedShowPois = _showPois;
    _visibleFeaturesCache = scene;
    return scene;
  }

  @override
  Widget build(BuildContext context) {
    final visibleFeatures = _visibleFeatures;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: testRegionCenter,
              initialZoom: _zoom,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_followUser) setState(() => _followUser = false);
                  _scheduleFetch();
                }
              },
            ),
            children: [
              // No filtered raster basemap: every visible mark is either a
              // WildBit pixel asset or a feature decoded from OSM data.
              const PixelTerrainBaseLayer(),
              OsmPixelCoastlineLayer(topology: _coastlineTopology),
              OsmPixelWaterLayer(features: visibleFeatures),
              OsmPixelWaterwayLayer(features: visibleFeatures),
              OsmPixelBiomeLayer(features: visibleFeatures),
              // Rocks sit above the ground fill but below routes and
              // foreground vegetation, matching the intended depth order.
              OsmPixelGeologyLayer(features: visibleFeatures),
              OsmPixelContourLayer(features: visibleFeatures),
              OsmPixelUrbanLayer(features: visibleFeatures),
              OsmPixelRouteLayer(features: visibleFeatures),
              OsmPixelBridgeLayer(features: visibleFeatures),
              // Bit sits above navigational geometry but below foreground
              // vegetation, so trunks and shrubs can occlude his feet.
              if (_lastFix != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _lastFix!.position,
                      width: 48,
                      height: 48,
                      child: const PixelPositionMarker(),
                    ),
                  ],
                ),
              // Geographic foreground scene: projected ground anchors are
              // split around Bit after map rotation, so occlusion is correct
              // from every bearing.
              OsmPixelTreeLayer(
                features: visibleFeatures,
                depthPivot: _bitRenderedPosition,
                middleChild: BitMapLayer(
                  key: _bitLayerKey,
                  locationService: widget.locationService,
                  controller: _bitController,
                  renderedPosition: _bitRenderedPosition,
                  onPositionUpdate: _onPositionUpdate,
                ),
              ),
              OsmPixelForegroundVegetationLayer(features: visibleFeatures),
              OsmPixelFlowerLayer(features: visibleFeatures),
              OsmPixelPoiLayer(
                features: visibleFeatures,
                onPoiTap: _openPoiDetails,
              ),
              const Scalebar(
                alignment: Alignment.bottomLeft,
                lineColor: Colors.white,
                textStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
              const Positioned(right: 12, bottom: 12, child: PixelMapLegend()),
            ],
          ),
          _TopStatusBar(
            followUser: _followUser,
            isLoading: _isLoadingFeatures,
            gpsReady: _lastFix != null,
            mapDataError: _mapDataError,
            usingLocalPreview: _usingLocalPreview,
            onLayersTap: _openLayersSheet,
          ),
          _ZoomControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnUser,
        child: Icon(_followUser ? Icons.my_location : Icons.location_searching),
      ),
    );
  }
}

class _PoiDetailsSheet extends StatelessWidget {
  const _PoiDetailsSheet({required this.poi, required this.onCenter});

  final Poi poi;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final title = poi.name.trim().isEmpty ? _typeLabel(poi.type) : poi.name;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: WildBitColors.forestGreen.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _typeIcon(poi.type),
                    color: WildBitColors.forestGreen,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _typeLabel(poi.type),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: WildBitColors.forestGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _PoiFactRow(
              icon: Icons.place_outlined,
              label: 'Coordinate',
              value:
                  '${poi.position.latitude.toStringAsFixed(5)}, '
                  '${poi.position.longitude.toStringAsFixed(5)}',
            ),
            const SizedBox(height: 10),
            const _PoiFactRow(
              icon: Icons.public,
              label: 'Fonte',
              value: 'OpenStreetMap',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WildBitColors.brown.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: WildBitColors.brown.withValues(alpha: .25),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: WildBitColors.brown),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dato cartografico informativo: la presenza sulla mappa '
                      'non certifica apertura, accessibilità, percorribilità o '
                      'sicurezza sul posto.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCenter,
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Centra sulla mappa'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(PoiType type) => switch (type) {
    PoiType.shelter => 'Rifugio o bivacco',
    PoiType.campsite => 'Area di sosta',
    PoiType.viewpoint => 'Punto panoramico',
    PoiType.guidepost => 'Cartello escursionistico',
    PoiType.parking => 'Parcheggio',
    PoiType.waterSource => 'Fonte d’acqua',
    PoiType.summit => 'Cima',
    PoiType.tree => 'Albero censito',
  };

  static IconData _typeIcon(PoiType type) => switch (type) {
    PoiType.shelter => Icons.cabin_outlined,
    PoiType.campsite => Icons.terrain,
    PoiType.viewpoint => Icons.landscape_outlined,
    PoiType.guidepost => Icons.signpost_outlined,
    PoiType.parking => Icons.local_parking,
    PoiType.waterSource => Icons.water_drop_outlined,
    PoiType.summit => Icons.filter_hdr,
    PoiType.tree => Icons.park_outlined,
  };
}

class _PoiFactRow extends StatelessWidget {
  const _PoiFactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: WildBitColors.forestGreen),
      const SizedBox(width: 10),
      SizedBox(
        width: 88,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      Expanded(child: Text(value)),
    ],
  );
}

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.followUser,
    required this.isLoading,
    required this.gpsReady,
    required this.mapDataError,
    required this.usingLocalPreview,
    required this.onLayersTap,
  });

  final bool followUser;
  final bool isLoading;
  final bool gpsReady;
  final String? mapDataError;
  final bool usingLocalPreview;
  final VoidCallback onLayersTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Flexible(
              child: _Pill(
                icon: mapDataError != null
                    ? Icons.cloud_off
                    : gpsReady
                    ? (isLoading ? Icons.sync : Icons.cloud_done)
                    : Icons.gps_not_fixed,
                label:
                    mapDataError ??
                    (gpsReady
                        ? (isLoading ? 'Aggiornamento...' : 'Dati pronti')
                        : 'Ricerca GPS in corso'),
                color: usingLocalPreview
                    ? WildBitColors.brown
                    : mapDataError != null
                    ? WildBitColors.brown
                    : WildBitColors.forestGreen,
              ),
            ),
            const Spacer(),
            _Pill(
              icon: followUser ? Icons.gps_fixed : Icons.gps_not_fixed,
              label: followUser ? 'Seguendo' : 'Libera',
              color: followUser
                  ? WildBitColors.forestGreen
                  : WildBitColors.brown,
            ),
            const SizedBox(width: 8),
            _RoundIconButton(icon: Icons.layers, onTap: onLayersTap),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: WildBitColors.forestGreen),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 100,
      child: Column(
        children: [
          _RoundIconButton(icon: Icons.add, onTap: onZoomIn),
          const SizedBox(height: 8),
          _RoundIconButton(icon: Icons.remove, onTap: onZoomOut),
        ],
      ),
    );
  }
}
