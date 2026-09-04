import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme/theme_provider.dart';
import '../../app/theme/wildbit_theme.dart';
import '../../data/osm/map_cell_grid.dart';
import '../../data/repositories/osm_map_data_repository.dart';
import '../../data/test_data/test_region.dart';
import '../../domain/entities/geo_bounds.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/geo_fix.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/entities/poi.dart';
import '../../domain/enums/poi_type.dart';
import '../../domain/routing/route_topology_graph.dart';
import '../../location/compass_heading_service.dart';
import '../../location/location_service.dart';
import '../../map_rendering/bit/bit_animation_controller.dart';
import '../../map_rendering/bit/bit_map_layer.dart';
import '../../map_rendering/assets/map_visual_asset_warmup.dart';
import '../../map_rendering/layers/osm_pixel_bridge_layer.dart';
import '../../map_rendering/layers/osm_pixel_biome_layer.dart';
import '../../map_rendering/layers/osm_pixel_coastline_layer.dart';
import '../../map_rendering/layers/osm_pixel_contour_layer.dart';
import '../../map_rendering/layers/osm_pixel_geology_layer.dart';
import '../../map_rendering/layers/osm_pixel_poi_layer.dart';
import '../../map_rendering/layers/osm_pixel_foreground_vegetation_layer.dart';
import '../../map_rendering/layers/osm_pixel_flower_layer.dart';
import '../../map_rendering/layers/osm_pixel_route_layer.dart';
import '../../map_rendering/layers/osm_pixel_route_label_layer.dart';
import '../../map_rendering/layers/osm_pixel_tree_layer.dart';
import '../../map_rendering/layers/osm_pixel_urban_layer.dart';
import '../../map_rendering/layers/osm_pixel_water_layer.dart';
import '../../map_rendering/layers/osm_pixel_waterway_layer.dart';
import '../../map_rendering/layers/pixel_terrain_base_layer.dart';
import '../../map_rendering/layers/pixel_map_legend.dart';
import '../../map_rendering/layers/pixel_position_marker.dart';
import '../../map_rendering/layers/pixel_recorded_track_layer.dart';
import '../../map_rendering/performance/map_rendering_budget.dart';
import '../../map_rendering/performance/map_frame_performance_monitor.dart';
import '../../map_rendering/performance/map_scene_metrics.dart';
import '../../map_rendering/performance/renderer_replay_bundle.dart';
import '../../map_rendering/composition/coastline_topology_composer.dart';
import '../../map_rendering/composition/osm_line_projector.dart';
import '../../map_rendering/composition/projected_depth_order.dart';
import '../../services/kokoro/wildbit_voice_service.dart';
import '../../services/renderer_replay_file_service.dart';
import '../../services/selected_route_controller.dart';
import '../../app/localization/app_localizations.dart';
import '../../services/track_recorder.dart';
import 'altitude_badge.dart';
import 'compass_fab.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.locationService,
    this.initialCenter,
    this.initialZoom,
    this.onViewportSnapshot,
  });

  final LocationService locationService;
  final LatLng? initialCenter;
  final double? initialZoom;
  final void Function(LatLng center, double zoom)? onViewportSnapshot;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _bitLayerKey = GlobalKey<BitMapLayerState>();
  final _bitRenderedPosition = ValueNotifier<LatLng?>(null);
  final _lineProjectionCache = ProjectedLineCache();
  final _urbanRenderCache = UrbanRenderCache();
  final _poiProjectionCache = PoiProjectionCache();
  final _foregroundVegetationRenderCache = ForegroundVegetationRenderCache();
  final _frameMonitor = MapFramePerformanceMonitor();
  late final _bitController = BitAnimationController();
  OsmMapDataRepository? _dataRepository;
  Timer? _fetchDebounce;
  Timer? _interactionIdle;
  DateTime? _lastMapGestureAt;
  Timer? _partialCoverageRetry;
  final Set<Timer> _featureFetchTimers = <Timer>{};
  Completer<void>? _featureRequestAbort;
  int _featureRequestId = 0;
  int? _lastStreamedFeatureRequestId;
  LatLng? _lastGpsFeatureFetch;
  final List<GeoBounds> _loadedFeatureRegions = [];
  final Map<String, _RetainedMapCell> _retainedMapCells = {};
  static const _maxRetainedMapCells = 6;

  MapFeatureCollection _features = const MapFeatureCollection(
    areas: [],
    lines: [],
    pois: [],
  );
  CoastlineTopology _coastlineTopology = const CoastlineTopology(
    chains: [],
    issues: [],
  );
  List<LineFeature> _coastlineLines = const [];
  bool _followUser = true;
  bool _isLoadingFeatures = false;
  String? _mapDataError;
  bool _usingLocalPreview = false;
  double _zoom = 16;
  // A location sample must update the marker and status, not rebuild the
  // complete pixel compositor. These two small overlays listen directly.
  final ValueNotifier<GeoFix?> _lastFix = ValueNotifier(null);

  bool _showTrails = true;
  bool _showRoads = true;
  bool _showPois = true;
  bool _showLabels = false;
  MapFeatureCollection? _visibleFeaturesCache;
  MapFeatureCollection? _visibleFeaturesSource;
  bool? _cachedShowTrails;
  bool? _cachedShowRoads;
  bool? _cachedShowPois;

  static const _poiAnnounceRadiusMeters = 150.0;
  // A public Overpass instance can be temporarily slow or overloaded. The
  // map must still become usable while the repository keeps the request alive
  // in the background and can populate its cache if it eventually succeeds.
  static const _featureFetchBudget = Duration(seconds: 10);
  static const _poiDistance = Distance();
  final _announcedPoiIds = <String>{};

  final _compassService = CompassHeadingService();
  StreamSubscription<double>? _compassSub;
  // Camera rotation can change for every pointer sample. Keeping it outside
  // the page State prevents a two-finger rotate from rebuilding every pixel
  // layer merely to turn the small compass icon.
  final ValueNotifier<double> _mapRotationDegrees = ValueNotifier(0);
  bool _headingModeActive = false;
  Timer? _ambientIdleTimer;
  SelectedRouteController? _selectedRouteController;
  Object? _lastFittedRouteTrail;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom ?? _zoom;
    MapRenderingBudget.setMapVisible(true);
    MapRenderingBudget.setAmbientIdle(false);
    WidgetsBinding.instance.addObserver(this);
    _compassSub = _compassService.headingStream.listen(_onCompassHeading);
    // The timing monitor is deliberately compact (a 60-frame rolling
    // window). It also runs in release so a slow field device can lower
    // purely decorative work rather than remaining under sustained pressure.
    _frameMonitor.stats.addListener(_onFrameStats);
    _frameMonitor.start();
    _scheduleAmbientIdle();
    // RootShell warms these on first launch. Repeating this idempotent call
    // means a Map recreated after a memory-pressure purge recovers its small
    // essentials asynchronously, without retaining the full renderer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(MapVisualAssetWarmup.warmup(context));
    });
  }

  void _onFrameStats() {
    final stats = _frameMonitor.stats.value;
    // A scene can be expensive even after a pan settles (for example a dense
    // forest whose ambient water/Bit frame is still costly). Apply the same
    // strictly decorative budget in that state as well; waiting for another
    // gesture used to leave slower phones at full workload indefinitely.
    if (stats.sampleCount == 0 || !MapRenderingBudget.mapVisible) return;
    final changed = MapRenderingBudget.configureFramePressure(
      averageBuildMicros: stats.averageBuildMicros,
      averageRasterMicros: stats.averageRasterMicros,
      p95FrameMicros: stats.p95FrameMicros,
      targetFrameMicros: _frameMonitor.targetFrameMicros,
    );
    // Only quality-tier changes rebuild the scene; the per-frame timings
    // themselves never create a setState loop.
    if (changed && mounted) setState(() {});
  }

  void _onCompassHeading(double headingDegrees) {
    if (!_headingModeActive) return;
    _mapController.rotate(-headingDegrees);
  }

  void _toggleHeadingMode() {
    setState(() => _headingModeActive = !_headingModeActive);
    if (_headingModeActive) {
      _compassService.start();
    } else {
      _compassService.stop();
      _mapController.rotate(0);
    }
  }

  // Backgrounding the app (or the screen locking) must not leave the
  // magnetometer/accelerometer sampling with nothing on screen to show for
  // it; heading mode resumes on its own once the app is visible again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    MapRenderingBudget.setAppActive(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) {
      _interactionIdle?.cancel();
      _interactionIdle = null;
      _lastMapGestureAt = null;
      _ambientIdleTimer?.cancel();
      _fetchDebounce?.cancel();
      // A backgrounded map must not keep a public Overpass request alive
      // through every fallback endpoint. It is pure battery/network work
      // while no hiker can see the result; resume below schedules a fresh,
      // viewport-relevant request if coverage is still missing.
      _cancelActiveFeatureRequest();
      MapRenderingBudget.setMapInteracting(false);
    } else {
      _scheduleAmbientIdle();
      _scheduleFetch();
    }
    if (!_headingModeActive) return;
    if (state == AppLifecycleState.resumed) {
      _compassService.start();
    } else {
      _compassService.stop();
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Never discard the current OSM scene: it contains the hiker's immediate
    // map evidence and must remain usable when connectivity is intermittent.
    // Everything released here is either a screen-space projection or a
    // decoded copy recoverable from the encrypted SQLite cache.
    _lineProjectionCache.clearTransient();
    _urbanRenderCache.clearTransient();
    _poiProjectionCache.clearTransient();
    _foregroundVegetationRenderCache.clearTransient();
    _dataRepository?.releaseTransientMemory();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    MapVisualAssetWarmup.releaseForMemoryPressure();
    debugPrint('WildBit renderer: memoria transitoria rilasciata');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_selectedRouteController == null) {
      _selectedRouteController = context.read<SelectedRouteController>();
      _selectedRouteController!.addListener(_onSelectedRouteChanged);
      _onSelectedRouteChanged();
    }
    if (_dataRepository != null) return;
    _dataRepository = context.read<OsmMapDataRepository>();
    // Do not query the Alpine preview coordinate during startup. Bit's first
    // GNSS update starts the real GPS-centred load; a manual map gesture still
    // schedules a viewport fetch when location is unavailable. The old eager
    // request raced the GPS request, doubled Overpass traffic and could commit
    // thousands of irrelevant features just as the camera moved to the user.
  }

  // Fits the camera once per newly selected route, not on every rebuild —
  // otherwise panning away from a long route while it downloads would keep
  // snapping the view back to it.
  void _onSelectedRouteChanged() {
    final controller = _selectedRouteController;
    if (controller == null) return;
    final trail = controller.trail;
    final geometry = controller.geometry;
    if (trail == null ||
        geometry == null ||
        geometry.length < 2 ||
        identical(trail, _lastFittedRouteTrail)) {
      return;
    }
    _lastFittedRouteTrail = trail;
    _fitCameraToRoute(geometry, attemptsLeft: 10);
  }

  // A route selected right as this screen is (re)created races FlutterMap's
  // own layout: on the very first post-frame callback its viewport can still
  // report MapCamera.kImpossibleSize, which silently turns the fit into a
  // no-op (fitCamera returns false rather than throwing) instead of the
  // expected zoom-to-route. Retrying on the next frame until a real size is
  // reported fixes this without guessing a fixed delay.
  void _fitCameraToRoute(List<LatLng> geometry, {required int attemptsLeft}) {
    if (attemptsLeft <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (_mapController.camera.nonRotatedSize == MapCamera.kImpossibleSize) {
          _fitCameraToRoute(geometry, attemptsLeft: attemptsLeft - 1);
          return;
        }
        final fitted = _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: geometry,
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 220),
            maxZoom: 15,
          ),
        );
        if (!fitted) {
          _fitCameraToRoute(geometry, attemptsLeft: attemptsLeft - 1);
        }
      } catch (_) {
        _fitCameraToRoute(geometry, attemptsLeft: attemptsLeft - 1);
      }
    });
  }

  @override
  void dispose() {
    try {
      final camera = _mapController.camera;
      widget.onViewportSnapshot?.call(camera.center, camera.zoom);
    } catch (_) {
      // The controller may not be attached if the shell changes tab during
      // the first map frame; there is simply no camera to preserve yet.
    }
    WidgetsBinding.instance.removeObserver(this);
    _selectedRouteController?.removeListener(_onSelectedRouteChanged);
    _fetchDebounce?.cancel();
    _interactionIdle?.cancel();
    _ambientIdleTimer?.cancel();
    _partialCoverageRetry?.cancel();
    for (final timer in _featureFetchTimers) {
      timer.cancel();
    }
    _featureFetchTimers.clear();
    _cancelActiveFeatureRequest();
    MapRenderingBudget.setMapInteracting(false);
    MapRenderingBudget.setMapVisible(false);
    _bitRenderedPosition.dispose();
    _lastFix.dispose();
    _mapRotationDegrees.dispose();
    _frameMonitor.stats.removeListener(_onFrameStats);
    _frameMonitor.dispose();
    _compassSub?.cancel();
    _compassService.dispose();
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
    await _fetchFeaturesIfNeeded(
      bounds,
      priorityPosition: _lastFix.value?.position ?? _bitRenderedPosition.value,
    );
  }

  Future<void> _fetchFeaturesIfNeeded(
    GeoBounds bounds, {
    LatLng? priorityPosition,
  }) async {
    if (_isFeatureAreaCovered(bounds)) return;
    await _fetchFeatures(bounds, priorityPosition: priorityPosition);
  }

  bool _isFeatureAreaCovered(GeoBounds bounds) =>
      MapCellGrid.isCoveredBy(bounds, _loadedFeatureRegions);

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
      priorityPosition: position,
    );
  }

  Future<void> _fetchFeatures(
    GeoBounds bounds, {
    LatLng? priorityPosition,
  }) async {
    final repository = _dataRepository;
    if (repository == null) return;
    _cancelActiveFeatureRequest();
    final abort = Completer<void>();
    _featureRequestAbort = abort;
    final requestId = ++_featureRequestId;

    setState(() => _isLoadingFeatures = true);
    final load = repository.loadFeatures(
      bounds,
      // Building footprints are useful only at walking/city zoom. Avoid
      // downloading thousands of urban polygons while the user is viewing a
      // broad hiking area; trails, water and terrain remain in the base query.
      // In WildBit urban footprints are deliberately secondary. Defer them
      // until an inspection-scale zoom: this protects the first render near
      // towns while the forest, water and every route remain available.
      includeBuildings: _mapController.camera.zoom >= 15.5,
      // Forest polygons stay in the base response at every zoom. Individual
      // OSM tree nodes are requested only close enough to distinguish them;
      // at broader hiking zoom they add network, memory and draw cost without
      // improving route legibility.
      includeIndividualTrees: _mapController.camera.zoom >= 15.5,
      shouldContinue: () => mounted && requestId == _featureRequestId,
      priorityPosition: priorityPosition,
      abortTrigger: abort.future,
      onCellLoaded: (cell, features) => _commitCellFeatures(
        features,
        cell: cell,
        requestBounds: bounds,
        requestId: requestId,
      ),
    );
    try {
      final features = await _withFetchBudget(load);
      _commitFeatures(features, bounds: bounds, requestId: requestId);
    } on TimeoutException {
      if (!mounted || requestId != _featureRequestId) return;
      // Do not mark the region as loaded: a timeout means the viewport still
      // needs a real response. In debug, the deterministic valley keeps the
      // renderer inspectable; in release, existing data remains visible and
      // the user gets an honest status instead of an empty green screen.
      setState(() {
        _isLoadingFeatures = false;
        if (kDebugMode && _features.areas.isEmpty && _features.lines.isEmpty) {
          _features = testRegionFeatures;
          _coastlineTopology = CoastlineTopologyComposer.compose(
            _features.lines.where(
              (line) => line.kind == MapFeatureKind.coastline,
            ),
          );
          _usingLocalPreview = true;
          _mapDataError = context.l10n.text('map.localPreviewDelayed');
        } else {
          _mapDataError = context.l10n.text('map.osmPending');
        }
      });
      _updatePartialCoverageRetry(bounds);
      return;
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
          _mapDataError = kDebugMode
              ? context.l10n.text('map.localPreviewUnavailable')
              : context.l10n.text('map.dataUnavailable');
        });
        _updatePartialCoverageRetry(bounds);
      }
    }
  }

  /// A cancellable equivalent of [Future.timeout]. Flutter's timeout helper
  /// owns an uncancellable Timer; keeping that timer alive after a map tab is
  /// disposed makes widget tests noisy and needlessly retains the state for
  /// the whole budget interval.
  Future<T> _withFetchBudget<T>(Future<T> operation) {
    final result = Completer<T>();
    late final Timer timer;
    void removeTimer() {
      timer.cancel();
      _featureFetchTimers.remove(timer);
    }

    timer = Timer(_featureFetchBudget, () {
      _featureFetchTimers.remove(timer);
      if (!result.isCompleted) {
        // This is a UI responsiveness budget, not a network cancellation.
        // Keeping the in-flight request alive lets the repository finish a
        // retry on another Overpass endpoint and publish its streamed cell
        // through onCellLoaded. A pan, disposal or a newer viewport still
        // calls _cancelActiveFeatureRequest and aborts the HTTP request.
        result.completeError(
          TimeoutException('OSM feature fetch exceeded $_featureFetchBudget'),
        );
      }
    });
    _featureFetchTimers.add(timer);
    operation.then(
      (value) {
        if (result.isCompleted) return;
        removeTimer();
        result.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (result.isCompleted) return;
        removeTimer();
        result.completeError(error, stackTrace);
      },
    );
    return result.future;
  }

  void _cancelActiveFeatureRequest() {
    final abort = _featureRequestAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _featureRequestAbort = null;
  }

  void _commitFeatures(
    MapFeatureCollection features, {
    required GeoBounds bounds,
    required int requestId,
  }) {
    if (!mounted || requestId != _featureRequestId) return;
    final repository = _dataRepository;
    if (repository == null) return;
    if (kDebugMode) {
      debugPrint(
        'WildBit OSM features: areas=${features.areas.length}, '
        'buildings=${features.areas.where((a) => a.kind == MapFeatureKind.building).length}, '
        'trees=${features.pois.where((p) => p.type == PoiType.tree).length}, '
        'lines=${features.lines.length}',
      );
    }
    final hasNoFeatures =
        features.areas.isEmpty &&
        features.lines.isEmpty &&
        features.pois.isEmpty;
    final useLocalPreview =
        kDebugMode && hasNoFeatures && repository.lastLoadError != null;
    final hasPartialCoverage = !_isFeatureAreaCovered(bounds);
    // Every available cell has already been committed through onCellLoaded.
    // Replacing the same scene here would rebuild all projected layers once
    // more just to dismiss the loading state, which the cell commit already
    // did. Keep the current collection identity and only maintain retry state.
    if (_lastStreamedFeatureRequestId == requestId && !useLocalPreview) {
      _updatePartialCoverageRetry(bounds);
      return;
    }
    final nextFeatures = useLocalPreview
        ? testRegionFeatures
        : _retainedMapCells.isEmpty
        ? _mergeFeatures(features, _features)
        : _mergeRetainedMapCells();
    final nextTopology = _topologyFor(nextFeatures);
    setState(() {
      _features = nextFeatures;
      _coastlineTopology = nextTopology;
      _isLoadingFeatures = false;
      _usingLocalPreview = useLocalPreview;
      _mapDataError = hasNoFeatures && repository.lastLoadError != null
          ? (useLocalPreview
                ? context.l10n.text('map.localPreviewUnavailable')
                : context.l10n.text('map.dataUnavailable'))
          : hasPartialCoverage
          ? context.l10n.text('map.partialRetry')
          : null;
    });
    _updatePartialCoverageRetry(bounds);
  }

  void _commitCellFeatures(
    MapFeatureCollection features, {
    required GeoBounds cell,
    required GeoBounds requestBounds,
    required int requestId,
  }) {
    if (!mounted || requestId != _featureRequestId) return;
    final key = MapCellGrid.keyFor(cell);
    _retainedMapCells[key] = _RetainedMapCell(cell: cell, features: features);
    _evictDistantMapCells();
    _lastStreamedFeatureRequestId = requestId;
    final nextFeatures = _mergeRetainedMapCells();
    final nextTopology = _topologyFor(nextFeatures);
    final hasPartialCoverage = !_isFeatureAreaCovered(requestBounds);
    setState(() {
      _features = nextFeatures;
      _coastlineTopology = nextTopology;
      _isLoadingFeatures = false;
      _loadedFeatureRegions
        ..clear()
        ..addAll(_retainedMapCells.values.map((entry) => entry.cell));
      _usingLocalPreview = false;
      _mapDataError = hasPartialCoverage
          ? context.l10n.text('map.partialLoading')
          : null;
    });
  }

  void _evictDistantMapCells() {
    if (_retainedMapCells.length <= _maxRetainedMapCells) return;
    final center = _mapController.camera.center;
    final ranked = _retainedMapCells.entries.toList()
      ..sort((first, second) {
        double distanceSquared(_RetainedMapCell entry) {
          final cellCenter = LatLng(
            (entry.cell.southWest.latitude + entry.cell.northEast.latitude) / 2,
            (entry.cell.southWest.longitude + entry.cell.northEast.longitude) /
                2,
          );
          final dLat = cellCenter.latitude - center.latitude;
          final dLng = cellCenter.longitude - center.longitude;
          return dLat * dLat + dLng * dLng;
        }

        final distance = distanceSquared(
          first.value,
        ).compareTo(distanceSquared(second.value));
        return distance != 0 ? distance : first.key.compareTo(second.key);
      });
    while (ranked.length > _maxRetainedMapCells) {
      _retainedMapCells.remove(ranked.removeLast().key);
    }
  }

  MapFeatureCollection _mergeRetainedMapCells() {
    final collections = _retainedMapCells.values.map((entry) => entry.features);
    return MapFeatureCollection(
      areas: [for (final collection in collections) ...collection.areas],
      lines: [for (final collection in collections) ...collection.lines],
      pois: [for (final collection in collections) ...collection.pois],
    ).deduplicated();
  }

  CoastlineTopology _topologyFor(MapFeatureCollection features) {
    final lines = features.lines
        .where((line) => line.kind == MapFeatureKind.coastline)
        .toList(growable: false);
    if (_sameCoastlineLines(lines, _coastlineLines)) {
      return _coastlineTopology;
    }
    _coastlineLines = lines;
    return CoastlineTopologyComposer.compose(lines);
  }

  bool _sameCoastlineLines(List<LineFeature> first, List<LineFeature> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) return false;
    }
    return true;
  }

  void _updatePartialCoverageRetry(GeoBounds bounds) {
    _partialCoverageRetry?.cancel();
    if (_isFeatureAreaCovered(bounds)) return;
    // Public Overpass endpoints apply a cooldown after a timeout/429/502. A
    // delayed retry fills only the still-missing cells without blocking the
    // map portion that is already usable.
    _partialCoverageRetry = Timer(const Duration(seconds: 45), () {
      if (!mounted || _isFeatureAreaCovered(bounds)) return;
      unawaited(_fetchFeaturesIfNeeded(bounds));
    });
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

  void _setMapInteracting(bool interacting) {
    if (interacting) {
      // FlutterMap can publish a camera sample for every pointer event. A
      // cancel/recreate debounce timer here used to allocate dozens of timers
      // per second while panning. Keep one low-frequency watcher instead.
      _lastMapGestureAt = DateTime.now();
      final changed = !MapRenderingBudget.mapInteracting;
      if (changed) {
        _ambientIdleTimer?.cancel();
        MapRenderingBudget.setMapInteracting(true);
        if (mounted) setState(() {});
      }
      _interactionIdle ??= Timer.periodic(const Duration(milliseconds: 120), (
        timer,
      ) {
        final last = _lastMapGestureAt;
        if (last != null &&
            DateTime.now().difference(last) <
                const Duration(milliseconds: 180)) {
          return;
        }
        timer.cancel();
        _interactionIdle = null;
        _lastMapGestureAt = null;
        if (!mounted) return;
        MapRenderingBudget.setMapInteracting(false);
        setState(() {});
        _scheduleAmbientIdle();
        // Do not query Overpass while the camera is still moving. The
        // first fetch after the gesture is idle also gives the renderer one
        // quiet frame to restore its full decorative budget.
        _scheduleFetch();
      });
      return;
    }

    _interactionIdle?.cancel();
    _interactionIdle = null;
    _lastMapGestureAt = null;
    final changed = MapRenderingBudget.mapInteracting;
    MapRenderingBudget.setMapInteracting(false);
    if (changed && mounted) setState(() {});
    _scheduleAmbientIdle();
  }

  void _scheduleAmbientIdle() {
    _ambientIdleTimer?.cancel();
    // Rendering a static map must not retain a periodic high-frequency paint
    // merely for small water highlights.  Keep a short grace period so the
    // cadence does not flap while a pan or pinch settles.
    _ambientIdleTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || MapRenderingBudget.mapInteracting) return;
      MapRenderingBudget.setAmbientIdle(true);
    });
  }

  void _onPositionUpdate(GeoFix point) {
    _lastFix.value = point;
    context.read<ThemeProvider>().onPositionUpdate(
      point.position.latitude,
      point.position.longitude,
    );
    _checkPoiProximity(point);
    if (_followUser && _shouldMoveFollowCamera(point)) {
      _mapController.move(point.position, _mapController.camera.zoom);
    }
    _loadFeaturesNearGpsPosition(point.position);
  }

  bool _shouldMoveFollowCamera(GeoFix point) {
    final displacement = _poiDistance.as(
      LengthUnit.Meter,
      _mapController.camera.center,
      point.position,
    );
    // Tiny GNSS drift used to move the FlutterMap camera for every sample,
    // reprojecting every pixel layer even while the hiker stood still. Keep
    // the map centred within the receiver's useful uncertainty instead.
    final accuracy = (point.accuracyMeters ?? 4.0).clamp(2.5, 12.0);
    return displacement >= accuracy;
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
        _lastFix.value?.position;
    if (freshFix != null) {
      _lastFix.value = freshFix;
    }
    if (position != null) {
      _mapController.move(position, _mapController.camera.zoom);
      unawaited(_fetchForGpsPosition(position));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('map.locationRequired'))),
    );
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + delta).clamp(3.0, 19.0);
    // [initialZoom] is consumed only when FlutterMap is first attached. The
    // controller move below owns the live camera, so rebuilding the full
    // compositing stack here is redundant.
    _zoom = newZoom;
    _mapController.move(camera.center, newZoom);
    // Consecutive +/- taps are one camera operation from the user's point of
    // view. Reuse the gesture debounce so they produce one OSM request for
    // the final zoom, rather than a burst of obsolete intermediate fetches.
    _scheduleFetch();
  }

  Future<void> _exportRendererReplay() async {
    if (!kDebugMode && !kProfileMode) return;
    final camera = _mapController.camera;
    final features = _visibleFeatures;
    try {
      final file = await RendererReplayFileService().save(
        RendererReplayBundle(
          capturedAt: DateTime.now(),
          center: camera.center,
          zoom: camera.zoom,
          rotation: camera.rotation,
          label: context.l10n.text('map.rendererSnapshot'),
          features: features,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.param('map.rendererSaved', {'path': file.path}),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.param('map.rendererExportFailed', {'error': '$error'}),
          ),
        ),
      );
    }
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
                    context.l10n.text('map.layersTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  CheckboxListTile(
                    value: _showTrails,
                    title: Text(context.l10n.text('map.trails')),
                    onChanged: (v) => setSheetState(
                      () => setState(() => _showTrails = v ?? true),
                    ),
                  ),
                  CheckboxListTile(
                    value: _showRoads,
                    title: Text(context.l10n.text('map.roads')),
                    onChanged: (v) => setSheetState(
                      () => setState(() => _showRoads = v ?? true),
                    ),
                  ),
                  CheckboxListTile(
                    value: _showPois,
                    title: Text(context.l10n.text('map.points')),
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
                              ? context.l10n
                                    .text('map.topologyVerified')
                                    .replaceAll(
                                      '{count}',
                                      '${topology.verifiedWayCount}',
                                    )
                              : context.l10n
                                    .text('map.topologyExcluded')
                                    .replaceAll(
                                      '{count}',
                                      '${topology.excludedWayCount}',
                                    ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.text('map.topologyDisclaimer'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (kDebugMode || kProfileMode) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Debug OSM: ${_features.areas.where((a) => a.kind == MapFeatureKind.building).length} edifici · '
                      '${_features.pois.where((p) => p.type == PoiType.tree).length} alberi',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Builder(
                      builder: (context) {
                        final metrics = MapSceneMetrics.fromFeatures(
                          _visibleFeatures,
                        );
                        return Text(
                          'Scena ${metrics.loadBand}: '
                          '${metrics.areaCount} aree · ${metrics.lineCount} vie · '
                          '${metrics.poiCount} POI · ${metrics.totalVertices} vertici '
                          '(${metrics.waterAreas} acqua, ${metrics.forestAreas} bosco)',
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      },
                    ),
                    ValueListenableBuilder<MapFrameStats>(
                      valueListenable: _frameMonitor.stats,
                      builder: (context, frameStats, child) => Text(
                        'Frame: ${_frameStatsLabel(frameStats)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      'Proiezione: ${_lineProjectionCache.hits} hit · '
                      '${_lineProjectionCache.misses} miss · '
                      '${(_lineProjectionCache.hitRate * 100).toStringAsFixed(0)}% cache',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _exportRendererReplay,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: Text(context.l10n.text('map.saveReplay')),
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

  String _frameStatsLabel(MapFrameStats stats) {
    if (stats.sampleCount == 0) return 'in attesa di campioni';
    final averageBuild = (stats.averageBuildMicros / 1000).toStringAsFixed(1);
    final averageRaster = (stats.averageRasterMicros / 1000).toStringAsFixed(1);
    final worst = (stats.worstFrameMicros / 1000).toStringAsFixed(1);
    final slowRate = (stats.slowFrameRate * 100).toStringAsFixed(0);
    return 'build ${averageBuild}ms · raster ${averageRaster}ms · '
        'max ${worst}ms · lenti $slowRate%';
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
    final media = MediaQuery.maybeOf(context);
    if (media != null) {
      MapRenderingBudget.configureDevice(
        logicalWidth: media.size.width,
        logicalHeight: media.size.height,
        devicePixelRatio: media.devicePixelRatio,
      );
    }
    final visibleFeatures = _visibleFeatures;
    final recorder = context.read<TrackRecorderController>();
    return Scaffold(
      body: Stack(
        children: [
          // The terrain texture is deliberately outside FlutterMap. It is
          // screen-anchored decoration, not geographic geometry; this keeps
          // the large repeated raster out of camera transforms during pan.
          const Positioned.fill(child: PixelTerrainBaseLayer()),
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter ?? testRegionCenter,
              initialZoom: _zoom,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: Colors.transparent,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _setMapInteracting(true);
                if ((camera.rotation - _mapRotationDegrees.value).abs() >= .1) {
                  _mapRotationDegrees.value = camera.rotation;
                }
                if (hasGesture) {
                  if (_followUser) setState(() => _followUser = false);
                  // A manual two-finger rotate overrides heading-follow —
                  // otherwise the next compass sample immediately fights it.
                  if (_headingModeActive) {
                    setState(() => _headingModeActive = false);
                  }
                }
              },
            ),
            children: [
              // No filtered raster basemap: every geographic mark is either
              // a WildBit pixel asset or a feature decoded from OSM data.
              _ViewportFeatureScope(
                features: visibleFeatures,
                builder: (context, viewportFeatures) => Stack(
                  fit: StackFit.expand,
                  children: [
                    OsmPixelCoastlineLayer(topology: _coastlineTopology),
                    OsmPixelWaterLayer(features: viewportFeatures),
                    OsmPixelWaterwayLayer(features: viewportFeatures),
                    OsmPixelBiomeLayer(features: viewportFeatures),
                    OsmPixelGeologyLayer(features: viewportFeatures),
                    OsmPixelContourLayer(features: viewportFeatures),
                    OsmPixelUrbanLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      renderCache: _urbanRenderCache,
                    ),
                    OsmPixelRouteLayer(
                      features: viewportFeatures,
                      projectionCache: _lineProjectionCache,
                    ),
                    OsmPixelBridgeLayer(features: viewportFeatures),
                    ListenableBuilder(
                      listenable: recorder,
                      builder: (context, _) =>
                          PixelRecordedTrackLayer(points: recorder.points),
                    ),
                    OsmPixelFlowerLayer(features: viewportFeatures),
                    OsmPixelForegroundVegetationLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      renderCache: _foregroundVegetationRenderCache,
                    ),
                    OsmPixelPoiLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      showLabels: false,
                      interactive: false,
                      projectionCache: _poiProjectionCache,
                    ),
                    ValueListenableBuilder<GeoFix?>(
                      valueListenable: _lastFix,
                      builder: (context, fix, child) => fix == null
                          ? const SizedBox.expand()
                          : MarkerLayer(
                              markers: [
                                Marker(
                                  point: fix.position,
                                  width: 48,
                                  height: 48,
                                  child: const PixelPositionMarker(),
                                ),
                              ],
                            ),
                    ),
                    OsmPixelTreeLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      middleChild: BitMapLayer(
                        key: _bitLayerKey,
                        locationService: widget.locationService,
                        controller: _bitController,
                        renderedPosition: _bitRenderedPosition,
                        onPositionUpdate: _onPositionUpdate,
                      ),
                    ),
                    // Low vegetation participates in the same depth split as
                    // tall trees: shrubs in front cover only Bit's lower
                    // silhouette, while shrubs behind him never float over
                    // the actor when the camera rotates.
                    OsmPixelForegroundVegetationLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      renderCache: _foregroundVegetationRenderCache,
                    ),
                    OsmPixelUrbanLayer(
                      features: viewportFeatures,
                      depthPivot: _bitRenderedPosition,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      renderCache: _urbanRenderCache,
                    ),
                    if (_showLabels)
                      OsmPixelRouteLabelLayer(
                        features: viewportFeatures,
                        projectionCache: _lineProjectionCache,
                      ),
                    OsmPixelPoiLayer(
                      features: viewportFeatures,
                      onPoiTap: _openPoiDetails,
                      depthPivot: _bitRenderedPosition,
                      showLabels: _showLabels,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      projectionCache: _poiProjectionCache,
                    ),
                  ],
                ),
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
              // Keep the legend above the cartographic scale.  The legend is
              // a wrapping panel and can grow to two rows on narrow phones;
              // placing it on the same bottom inset as Scalebar made the two
              // overlays collide and obscured the real-world distance label.
              const Positioned(right: 12, bottom: 60, child: PixelMapLegend()),
              // A route selected in Explore, previewed here before/while its
              // offline corridor downloads. Reuses the recorded-track
              // painter — same "a highlighted line over the terrain" need,
              // just fed a route's geometry instead of a live GPS trace.
              Consumer<SelectedRouteController>(
                builder: (context, selectedRoute, _) {
                  final geometry = selectedRoute.geometry;
                  if (geometry == null) return const SizedBox.shrink();
                  return PixelRecordedTrackLayer(
                    points: [
                      for (final (index, point) in geometry.indexed)
                        GeoFix(
                          position: point,
                          timestamp: DateTime.fromMillisecondsSinceEpoch(index),
                        ),
                    ],
                    color: const Color(0xFF4FC3F7),
                  );
                },
              ),
            ],
          ),
          ValueListenableBuilder<GeoFix?>(
            valueListenable: _lastFix,
            builder: (context, fix, _) => _TopStatusBar(
              followUser: _followUser,
              isLoading: _isLoadingFeatures,
              gpsReady: fix != null,
              mapDataError: _mapDataError,
              usingLocalPreview: _usingLocalPreview,
              onLayersTap: _openLayersSheet,
            ),
          ),
          // Right-side instrument column, bottom to top: GPS-centring FAB
          // (Scaffold-managed, ~16-72), altitude, label toggle, zoom +/-,
          // compass. Each entry's `bottom` is the previous one's top plus an
          // 8px gap — adding a new control here means computing its slot
          // from this same stack, not guessing a value that happens to look
          // free in one screenshot.
          Positioned(
            right: 12,
            bottom: 80,
            child: ValueListenableBuilder<GeoFix?>(
              valueListenable: _lastFix,
              builder: (context, fix, _) =>
                  AltitudeBadge(altitudeMeters: fix?.altitudeMeters),
            ),
          ),
          _LabelToggleControl(
            enabled: _showLabels,
            onTap: () => setState(() => _showLabels = !_showLabels),
          ),
          _ZoomControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
          ),
          Positioned(
            right: 12,
            bottom: 288,
            child: ValueListenableBuilder<double>(
              valueListenable: _mapRotationDegrees,
              builder: (context, rotationDegrees, _) => CompassFab(
                rotationDegrees: rotationDegrees,
                headingModeActive: _headingModeActive,
                onTap: _toggleHeadingMode,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 76,
            bottom: 12,
            child: Consumer<SelectedRouteController>(
              builder: (context, selectedRoute, _) {
                if (selectedRoute.trail == null) {
                  return const SizedBox.shrink();
                }
                return _RouteDownloadCard(controller: selectedRoute);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<GeoFix?>(
        valueListenable: _lastFix,
        builder: (context, fix, _) => FloatingActionButton(
          onPressed: _centerOnUser,
          child: Icon(
            _followUser && fix != null
                ? Icons.my_location
                : Icons.location_searching,
          ),
        ),
      ),
    );
  }
}

class _RetainedMapCell {
  const _RetainedMapCell({required this.cell, required this.features});

  final GeoBounds cell;
  final MapFeatureCollection features;
}

typedef _ViewportFeatureBuilder =
    Widget Function(BuildContext context, MapFeatureCollection features);

/// Keeps the heavy pixel compositor on a retained geographic window around
/// the camera. Network/cache collections may contain thousands of buildings
/// from four 2 km cells; decorative layers must never rebuild candidates from
/// all of them when only a small phone viewport is visible.
class _ViewportFeatureScope extends StatefulWidget {
  const _ViewportFeatureScope({required this.features, required this.builder});

  final MapFeatureCollection features;
  final _ViewportFeatureBuilder builder;

  @override
  State<_ViewportFeatureScope> createState() => _ViewportFeatureScopeState();
}

class _ViewportFeatureScopeState extends State<_ViewportFeatureScope> {
  MapFeatureCollection? _source;
  MapFeatureCollection? _viewportFeatures;
  LatLngBounds? _retainedBounds;

  @override
  Widget build(BuildContext context) {
    final cameraBounds = MapCamera.of(context).visibleBounds;
    final sourceChanged = !identical(_source, widget.features);
    if (sourceChanged || !_contains(_retainedBounds, cameraBounds)) {
      _source = widget.features;
      _retainedBounds = _expanded(cameraBounds);
      final next = _cull(widget.features, _retainedBounds!);
      final previous = _viewportFeatures;
      // A neighbouring cell can finish without contributing anything to this
      // retained window. Preserve collection identity in that case so tree,
      // shrub and flower layers do not regenerate their candidates.
      if (previous == null || !_sameCollection(previous, next)) {
        _viewportFeatures = next;
        MapRenderingBudget.configureScene(next);
        if (kDebugMode) {
          debugPrint(
            'WildBit renderer viewport: '
            'aree ${widget.features.areas.length}->${next.areas.length}, '
            'linee ${widget.features.lines.length}->${next.lines.length}, '
            'poi ${widget.features.pois.length}->${next.pois.length}',
          );
        }
      }
    }
    return widget.builder(context, _viewportFeatures!);
  }

  LatLngBounds _expanded(LatLngBounds bounds) {
    final latitudePadding = math.max(
      (bounds.north - bounds.south) * .25,
      .0015,
    );
    final longitudePadding = math.max((bounds.east - bounds.west) * .25, .0015);
    return LatLngBounds(
      LatLng(bounds.south - latitudePadding, bounds.west - longitudePadding),
      LatLng(bounds.north + latitudePadding, bounds.east + longitudePadding),
    );
  }

  bool _contains(LatLngBounds? outer, LatLngBounds inner) =>
      outer != null &&
      outer.south <= inner.south &&
      outer.north >= inner.north &&
      MapRenderingBudget.longitudeIntervalContains(
        outer.west,
        outer.east,
        inner.west,
        inner.east,
      );

  MapFeatureCollection _cull(
    MapFeatureCollection features,
    LatLngBounds bounds,
  ) => MapFeatureCollection(
    areas: features.areas
        .where((area) => MapRenderingBudget.areaMayBeVisible(area, bounds))
        .toList(growable: false),
    lines: features.lines
        .where((line) => MapRenderingBudget.lineMayBeVisible(line, bounds))
        .toList(growable: false),
    pois: features.pois
        .where((poi) => bounds.contains(poi.position))
        .toList(growable: false),
  );

  bool _sameCollection(
    MapFeatureCollection first,
    MapFeatureCollection second,
  ) =>
      _sameItems(first.areas, second.areas) &&
      _sameItems(first.lines, second.lines) &&
      _sameItems(first.pois, second.pois);

  bool _sameItems<T>(List<T> first, List<T> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) return false;
    }
    return true;
  }
}

class _PoiDetailsSheet extends StatelessWidget {
  const _PoiDetailsSheet({required this.poi, required this.onCenter});

  final Poi poi;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final title = poi.name.trim().isEmpty
        ? _typeLabel(poi.type, context)
        : poi.name;
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
                        _typeLabel(poi.type, context),
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
              label: context.l10n.text('map.coordinates'),
              value:
                  '${poi.position.latitude.toStringAsFixed(5)}, '
                  '${poi.position.longitude.toStringAsFixed(5)}',
            ),
            ..._metadataFacts(poi, context),
            const SizedBox(height: 10),
            _PoiFactRow(
              icon: Icons.public,
              label: context.l10n.text('map.source'),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: WildBitColors.brown),
                  SizedBox(width: 10),
                  Expanded(child: Text(context.l10n.text('map.poiWarning'))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCenter,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(context.l10n.text('map.center')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(PoiType type, BuildContext context) =>
      switch (type) {
        PoiType.shelter =>
          context.l10n.languageCode == 'it' ? 'Rifugio o bivacco' : 'Shelter',
        PoiType.campsite =>
          context.l10n.languageCode == 'it' ? 'Area di sosta' : 'Campsite',
        PoiType.viewpoint =>
          context.l10n.languageCode == 'it' ? 'Punto panoramico' : 'Viewpoint',
        PoiType.guidepost =>
          context.l10n.languageCode == 'it'
              ? 'Cartello escursionistico'
              : 'Trail signpost',
        PoiType.parking =>
          context.l10n.languageCode == 'it' ? 'Parcheggio' : 'Parking',
        PoiType.waterSource =>
          context.l10n.languageCode == 'it' ? 'Fonte d’acqua' : 'Water source',
        PoiType.summit => context.l10n.languageCode == 'it' ? 'Cima' : 'Summit',
        PoiType.tree =>
          context.l10n.languageCode == 'it' ? 'Albero censito' : 'Mapped tree',
        PoiType.ford => context.l10n.languageCode == 'it' ? 'Guado' : 'Ford',
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
    PoiType.ford => Icons.waterfall_chart_outlined,
  };

  static List<Widget> _metadataFacts(Poi poi, BuildContext context) {
    final metadata = poi.metadata;
    final facts = <Widget>[];
    void add(IconData icon, String label, String value) {
      facts
        ..add(const SizedBox(height: 10))
        ..add(_PoiFactRow(icon: icon, label: label, value: value));
    }

    final elevation = metadata.elevationMeters;
    if (elevation != null) {
      final formatted = elevation == elevation.roundToDouble()
          ? elevation.toStringAsFixed(0)
          : elevation.toStringAsFixed(1);
      add(
        Icons.height,
        context.l10n.languageCode == 'it' ? 'Quota OSM' : 'OSM elevation',
        '$formatted m',
      );
    }
    final access = metadata.access;
    if (access != null) {
      add(
        Icons.directions_walk,
        context.l10n.languageCode == 'it' ? 'Accesso OSM' : 'OSM access',
        _accessLabel(access, context),
      );
    }
    if (poi.type == PoiType.waterSource || metadata.drinkingWater != null) {
      add(
        Icons.water_drop_outlined,
        context.l10n.languageCode == 'it' ? 'Potabilità' : 'Drinking water',
        switch (metadata.drinkingWater) {
          true =>
            context.l10n.languageCode == 'it'
                ? 'Indicata come potabile su OSM'
                : 'Marked as drinkable on OSM',
          false =>
            context.l10n.languageCode == 'it'
                ? 'Indicata come non potabile su OSM'
                : 'Marked as non-drinkable on OSM',
          null =>
            context.l10n.languageCode == 'it'
                ? 'Non indicata su OSM'
                : 'Not indicated on OSM',
        },
      );
    }
    final operatorName = metadata.operatorName;
    if (operatorName != null) {
      add(
        Icons.badge_outlined,
        context.l10n.languageCode == 'it' ? 'Gestore OSM' : 'OSM operator',
        operatorName,
      );
    }
    final openingHours = metadata.openingHours;
    if (openingHours != null) {
      add(
        Icons.schedule,
        context.l10n.languageCode == 'it' ? 'Orari OSM' : 'OSM opening hours',
        openingHours,
      );
    }
    return facts;
  }

  static String _accessLabel(String value, BuildContext context) =>
      switch (value) {
        'yes' =>
          context.l10n.languageCode == 'it'
              ? 'Consentito (tag: yes)'
              : 'Allowed (tag: yes)',
        'permissive' =>
          context.l10n.languageCode == 'it'
              ? 'Consentito dal proprietario (tag: permissive)'
              : 'Permitted by owner (tag: permissive)',
        'private' =>
          context.l10n.languageCode == 'it'
              ? 'Privato (tag: private)'
              : 'Private (tag: private)',
        'no' =>
          context.l10n.languageCode == 'it'
              ? 'Vietato (tag: no)'
              : 'Not allowed (tag: no)',
        'customers' =>
          context.l10n.languageCode == 'it'
              ? 'Riservato ai clienti (tag: customers)'
              : 'Customers only (tag: customers)',
        'destination' =>
          context.l10n.languageCode == 'it'
              ? 'Solo destinazione (tag: destination)'
              : 'Destination only (tag: destination)',
        'permit' =>
          context.l10n.languageCode == 'it'
              ? 'Con permesso (tag: permit)'
              : 'With permit (tag: permit)',
        _ =>
          context.l10n.languageCode == 'it'
              ? 'Tag OSM: $value'
              : 'OSM tag: $value',
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
                        ? (isLoading
                              ? context.l10n.text('map.statusUpdating')
                              : context.l10n.text('map.statusReady'))
                        : context.l10n.text('map.statusSearchingGps')),
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
              label: followUser
                  ? context.l10n.text('map.following')
                  : context.l10n.text('map.free'),
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
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 34,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(icon, size: iconSize, color: WildBitColors.forestGreen),
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  // Matches CompassFab's 44px diameter so the whole right-side button
  // column reads as one family of controls instead of two different sizes.
  static const _buttonSize = 44.0;
  static const _iconSize = 22.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      // Sits above the altitude badge and label toggle, below the compass —
      // see the instrument-column comment in _MapScreenState.build.
      bottom: 184,
      child: Column(
        children: [
          _RoundIconButton(
            icon: Icons.add,
            onTap: onZoomIn,
            size: _buttonSize,
            iconSize: _iconSize,
          ),
          const SizedBox(height: 8),
          _RoundIconButton(
            icon: Icons.remove,
            onTap: onZoomOut,
            size: _buttonSize,
            iconSize: _iconSize,
          ),
        ],
      ),
    );
  }
}

class _LabelToggleControl extends StatelessWidget {
  const _LabelToggleControl({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = enabled
        ? context.l10n.text('map.labelHide')
        : context.l10n.text('map.labelShow');
    return Positioned(
      right: 12,
      // Sits above the altitude badge, below zoom — see the instrument-
      // column comment in _MapScreenState.build.
      bottom: 132,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: enabled
                ? WildBitColors.forestGreen
                : Colors.white.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  enabled ? Icons.label : Icons.label_off_outlined,
                  color: enabled ? Colors.white : WildBitColors.forestGreen,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Route preview + offline-corridor download, shown over the map once a
/// curated route is selected from Explore.
class _RouteDownloadCard extends StatelessWidget {
  const _RouteDownloadCard({required this.controller});

  final SelectedRouteController controller;

  /// A ~2km cell's cached OSM payload varies a lot with terrain density —
  /// this is a labelled estimate, not a measured figure, so it is shown as
  /// a range rather than a single falsely-precise number.
  static const _minMbPerCell = 0.2;
  static const _maxMbPerCell = 1.0;

  @override
  Widget build(BuildContext context) {
    final trail = controller.trail;
    if (trail == null) return const SizedBox.shrink();
    final cellCount = controller.corridorCellCount ?? 0;
    final minMb = (cellCount * _minMbPerCell).round();
    final maxMb = (cellCount * _maxMbPerCell).round();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.route, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusLine(context, cellCount, minMb, maxMb),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (controller.downloadState ==
                      RouteDownloadState.downloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: cellCount == 0
                            ? null
                            : (controller.downloadedCells +
                                      controller.failedCells) /
                                  cellCount,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _trailingAction(context, cellCount),
            IconButton(
              tooltip: context.l10n.text('map.close'),
              onPressed: () => context.read<SelectedRouteController>().clear(),
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trailingAction(BuildContext context, int cellCount) {
    switch (controller.downloadState) {
      case RouteDownloadState.idle:
        return TextButton(
          onPressed: cellCount == 0 ? null : controller.startDownload,
          child: Text(context.l10n.text('map.download')),
        );
      case RouteDownloadState.downloading:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case RouteDownloadState.done:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.check_circle, color: WildBitColors.forestGreen),
        );
      case RouteDownloadState.failed:
        return TextButton(
          onPressed: controller.startDownload,
          child: Text(context.l10n.text('common.retry')),
        );
    }
  }

  String _statusLine(
    BuildContext context,
    int cellCount,
    int minMb,
    int maxMb,
  ) {
    switch (controller.downloadState) {
      case RouteDownloadState.idle:
        return cellCount == 0
            ? context.l10n.text('map.routeOfflineUnavailable')
            : context.l10n.param('map.routeOfflineEstimate', {
                'count': '$cellCount',
                'min': '$minMb',
                'max': '$maxMb',
              });
      case RouteDownloadState.downloading:
        return context.l10n.param('map.routeDownloadProgress', {
          'done': '${controller.downloadedCells + controller.failedCells}',
          'count': '$cellCount',
        });
      case RouteDownloadState.done:
        return context.l10n.param('map.routeOfflineReady', {
          'count': '$cellCount',
        });
      case RouteDownloadState.failed:
        return context.l10n.param('map.routeDownloadFailed', {
          'failed': '${controller.failedCells}',
          'count': '$cellCount',
        });
    }
  }
}
