import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'data/test_data/mixed_preview_region.dart';
import 'data/test_data/osm_replay_region.dart';
import 'data/test_data/renderer_stress_region.dart';
import 'data/test_data/test_region.dart';
import 'domain/entities/map_feature_collection.dart';
import 'domain/enums/map_feature_kind.dart';
import 'map_rendering/bit/bit_animation_controller.dart';
import 'map_rendering/bit/bit_cursor.dart';
import 'map_rendering/composition/coastline_topology_composer.dart';
import 'map_rendering/composition/osm_line_projector.dart';
import 'map_rendering/composition/projected_depth_order.dart';
import 'map_rendering/layers/osm_pixel_biome_layer.dart';
import 'map_rendering/layers/osm_pixel_bridge_layer.dart';
import 'map_rendering/layers/osm_pixel_coastline_layer.dart';
import 'map_rendering/layers/osm_pixel_contour_layer.dart';
import 'map_rendering/layers/osm_pixel_flower_layer.dart';
import 'map_rendering/layers/osm_pixel_foreground_vegetation_layer.dart';
import 'map_rendering/layers/osm_pixel_geology_layer.dart';
import 'map_rendering/layers/osm_pixel_poi_layer.dart';
import 'map_rendering/layers/osm_pixel_route_label_layer.dart';
import 'map_rendering/layers/osm_pixel_route_layer.dart';
import 'map_rendering/layers/osm_pixel_tree_layer.dart';
import 'map_rendering/layers/osm_pixel_urban_layer.dart';
import 'map_rendering/layers/osm_pixel_water_layer.dart';
import 'map_rendering/layers/osm_pixel_waterway_layer.dart';
import 'map_rendering/layers/pixel_terrain_base_layer.dart';
import 'map_rendering/performance/map_frame_performance_monitor.dart';
import 'map_rendering/performance/map_rendering_budget.dart';
import 'map_rendering/performance/map_scene_metrics.dart';
import 'services/renderer_replay_file_service.dart';

/// Network-free renderer exercise target.
///
/// `flutter run --profile -t lib/renderer_profile_main.dart -d <device>`
/// runs the production compositor against a deterministic local valley, so
/// timing results cannot be caused by GPS, Overpass, cache or persistence.
void main() => runApp(const RendererProfileApp());

class RendererProfileApp extends StatelessWidget {
  const RendererProfileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const RendererProfileScreen(),
  );
}

class RendererProfileScreen extends StatefulWidget {
  const RendererProfileScreen({super.key});

  @override
  State<RendererProfileScreen> createState() => _RendererProfileScreenState();
}

class _RendererProfileScreenState extends State<RendererProfileScreen> {
  final MapController _mapController = MapController();
  final ValueNotifier<LatLng?> _actorPosition = ValueNotifier<LatLng?>(
    const LatLng(46.0672, 11.1215),
  );
  final MapFramePerformanceMonitor _frameMonitor = MapFramePerformanceMonitor();
  final BitAnimationController _bitController = BitAnimationController();
  final ProjectedLineCache _lineProjectionCache = ProjectedLineCache();
  final UrbanRenderCache _urbanRenderCache = UrbanRenderCache();
  final PoiProjectionCache _poiProjectionCache = PoiProjectionCache();
  final ForegroundVegetationRenderCache _foregroundVegetationRenderCache =
      ForegroundVegetationRenderCache();
  Timer? _interactionIdle;
  Timer? _benchmarkTimer;
  Timer? _benchmarkSettle;
  bool _showDiagnostics = true;
  bool _benchmarkRunning = false;
  bool _layerSweepRunning = false;
  MapFrameStats? _lastBenchmarkStats;
  String? _lastBenchmarkScene;
  final Map<_ProfilePassPreset, MapFrameStats> _layerBenchmarkStats =
      <_ProfilePassPreset, MapFrameStats>{};
  _ProfileScene _scene = _ProfileScene.standard;
  _ProfilePassPreset _passPreset = _ProfilePassPreset.full;
  String? _loadedReplayLabel;
  late MapFeatureCollection _features = mixedPreviewFeatures;

  late CoastlineTopology _coastline = CoastlineTopologyComposer.compose(
    _features.lines.where((line) => line.kind == MapFeatureKind.coastline),
  );

  @override
  void initState() {
    super.initState();
    MapRenderingBudget.configureScene(_features);
    MapRenderingBudget.setMapVisible(true);
    _bitController.reportMovement(isMoving: false);
    _frameMonitor.stats.addListener(_onFrameStats);
    _frameMonitor.start();
  }

  void _onFrameStats() {
    final stats = _frameMonitor.stats.value;
    if (stats.sampleCount == 0 || !MapRenderingBudget.mapVisible) return;
    final qualityChanged = MapRenderingBudget.configureFramePressure(
      averageBuildMicros: stats.averageBuildMicros,
      averageRasterMicros: stats.averageRasterMicros,
      p95FrameMicros: stats.p95FrameMicros,
      targetFrameMicros: _frameMonitor.targetFrameMicros,
    );
    if (qualityChanged && mounted) setState(() {});
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    MapRenderingBudget.setMapInteracting(true);
    _interactionIdle?.cancel();
    _interactionIdle = Timer(const Duration(milliseconds: 240), () {
      MapRenderingBudget.setMapInteracting(false);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _interactionIdle?.cancel();
    _benchmarkTimer?.cancel();
    _benchmarkSettle?.cancel();
    MapRenderingBudget.setMapInteracting(false);
    MapRenderingBudget.setMapVisible(false);
    _actorPosition.dispose();
    _bitController.dispose();
    _frameMonitor.stats.removeListener(_onFrameStats);
    _frameMonitor.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(3.0, 19.0));
  }

  void _rotateBy(double delta) {
    _mapController.rotate(_mapController.camera.rotation + delta);
  }

  Future<MapFrameStats?> _runBenchmark() {
    if (_benchmarkRunning) return Future<MapFrameStats?>.value(null);
    _benchmarkTimer?.cancel();
    _benchmarkSettle?.cancel();
    _frameMonitor.reset();
    setState(() => _benchmarkRunning = true);
    MapRenderingBudget.setMapInteracting(true);
    final origin = _mapController.camera.center;
    final originZoom = _mapController.camera.zoom;
    final originRotation = _mapController.camera.rotation;
    final benchmarkScene =
        '${_loadedReplayLabel ?? _scene.label} · ${_passPreset.label}';
    var step = 0;
    // A 4.3 second bounded camera loop deliberately resembles a user
    // inspecting nearby trail choices: two small pans, a zoom change and
    // rotation. It is deterministic, does not fetch data and always restores
    // the full-detail tier at the end.
    final completion = Completer<MapFrameStats?>();
    _benchmarkTimer = Timer.periodic(const Duration(milliseconds: 120), (
      timer,
    ) {
      const totalSteps = 36;
      final angle = step * math.pi * 2 / totalSteps;
      final center = LatLng(
        origin.latitude + math.sin(angle) * .0011,
        origin.longitude + math.cos(angle * 1.4) * .00145,
      );
      final zoom = (originZoom + math.sin(angle * 2) * .7).clamp(3.0, 19.0);
      _mapController.move(center, zoom);
      if (step % 4 == 0) {
        _mapController.rotate(originRotation + (step / 4) * 45);
      }
      step++;
      if (step < totalSteps) return;
      timer.cancel();
      _benchmarkTimer = null;
      MapRenderingBudget.setMapInteracting(false);
      if (mounted) setState(() => _benchmarkRunning = false);
      // FrameTiming arrives after raster work. Wait briefly, then freeze the
      // exact result for a comparable screenshot/log on another device.
      _benchmarkSettle = Timer(const Duration(milliseconds: 450), () {
        _frameMonitor.flush();
        final stats = _frameMonitor.stats.value;
        if (!mounted) {
          completion.complete(null);
          return;
        }
        setState(() {
          _lastBenchmarkStats = stats;
          _lastBenchmarkScene = benchmarkScene;
        });
        // Do not leave a test pass in a shifted/rotated camera state. This
        // keeps the next layer measurement directly comparable.
        _mapController.move(origin, originZoom);
        _mapController.rotate(originRotation);
        completion.complete(stats);
      });
    });
    return completion.future;
  }

  Future<void> _runLayerSweep() async {
    if (_benchmarkRunning || _layerSweepRunning) return;
    final originalPass = _passPreset;
    setState(() {
      _layerSweepRunning = true;
      _layerBenchmarkStats.clear();
    });
    try {
      for (final pass in _ProfilePassPreset.values) {
        if (!mounted) return;
        MapRenderingBudget.resetFramePressure();
        setState(() => _passPreset = pass);
        // Let the pass settle once before collecting its scripted movement;
        // otherwise shader/cache warm-up would be attributed to that layer.
        await Future<void>.delayed(const Duration(milliseconds: 650));
        final stats = await _runBenchmark();
        if (!mounted) return;
        if (stats != null) {
          setState(() => _layerBenchmarkStats[pass] = stats);
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      MapRenderingBudget.resetFramePressure();
      if (mounted) {
        setState(() {
          _passPreset = originalPass;
          _layerSweepRunning = false;
        });
      }
    }
  }

  void _nextScene() {
    setState(() {
      _scene = _ProfileScene
          .values[(_scene.index + 1) % _ProfileScene.values.length];
      _features = _scene.features;
      _loadedReplayLabel = null;
      _coastline = CoastlineTopologyComposer.compose(
        _features.lines.where((line) => line.kind == MapFeatureKind.coastline),
      );
      MapRenderingBudget.configureScene(_features);
    });
  }

  void _nextPassPreset() {
    setState(() {
      _passPreset = _ProfilePassPreset
          .values[(_passPreset.index + 1) % _ProfilePassPreset.values.length];
      _lastBenchmarkStats = null;
      _lastBenchmarkScene = null;
    });
  }

  Future<void> _openReplay() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result.singleOrNull?.path;
    if (path == null) return;
    try {
      final replay = await RendererReplayFileService().load(File(path));
      if (!mounted) return;
      setState(() {
        _features = replay.features;
        _loadedReplayLabel = replay.label ?? 'Replay importato';
        _coastline = CoastlineTopologyComposer.compose(
          _features.lines.where(
            (line) => line.kind == MapFeatureKind.coastline,
          ),
        );
        MapRenderingBudget.configureScene(_features);
      });
      _mapController.move(replay.center, replay.zoom);
      _mapController.rotate(replay.rotation);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replay non valido: ${error.message}')),
      );
    } on IOException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile leggere il replay: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    MapRenderingBudget.configureDevice(
      logicalWidth: media.size.width,
      logicalHeight: media.size.height,
      devicePixelRatio: media.devicePixelRatio,
    );
    final passes = _passPreset;
    return Scaffold(
      body: Stack(
        children: [
          if (passes.drawTerrainBase)
            const Positioned.fill(child: PixelTerrainBaseLayer()),
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: testRegionCenter,
              initialZoom: 15.5,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: Colors.transparent,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              Stack(
                fit: StackFit.expand,
                children: [
                  if (passes.drawCoastline)
                    OsmPixelCoastlineLayer(topology: _coastline),
                  if (passes.drawWater) OsmPixelWaterLayer(features: _features),
                  if (passes.drawWater)
                    OsmPixelWaterwayLayer(features: _features),
                  if (passes.drawBiome) OsmPixelBiomeLayer(features: _features),
                  if (passes.drawGeology)
                    OsmPixelGeologyLayer(features: _features),
                  if (passes.drawContours)
                    OsmPixelContourLayer(features: _features),
                  if (passes.drawUrban)
                    OsmPixelUrbanLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      renderCache: _urbanRenderCache,
                    ),
                  if (passes.drawRoutes)
                    OsmPixelRouteLayer(
                      features: _features,
                      projectionCache: _lineProjectionCache,
                    ),
                  if (passes.drawRoutes)
                    OsmPixelBridgeLayer(features: _features),
                  if (passes.drawVegetation)
                    OsmPixelFlowerLayer(features: _features),
                  if (passes.drawVegetation)
                    OsmPixelForegroundVegetationLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      renderCache: _foregroundVegetationRenderCache,
                    ),
                  if (passes.drawPois)
                    OsmPixelPoiLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.behindPivot,
                      showLabels: false,
                      interactive: false,
                      projectionCache: _poiProjectionCache,
                    ),
                  if (passes.drawVegetation)
                    OsmPixelTreeLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      middleChild: _ProfileBitActor(
                        position: _actorPosition.value!,
                        controller: _bitController,
                      ),
                    ),
                  if (passes.drawVegetation)
                    OsmPixelForegroundVegetationLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      renderCache: _foregroundVegetationRenderCache,
                    ),
                  if (passes.drawUrban)
                    OsmPixelUrbanLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      renderCache: _urbanRenderCache,
                    ),
                  if (passes.drawRoutes)
                    OsmPixelRouteLabelLayer(
                      features: _features,
                      projectionCache: _lineProjectionCache,
                    ),
                  if (passes.drawPois)
                    OsmPixelPoiLayer(
                      features: _features,
                      depthPivot: _actorPosition,
                      slice: ProjectedDepthSlice.inFrontOfPivot,
                      projectionCache: _poiProjectionCache,
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 12,
            right: 12,
            child: _ProfileToolbar(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
              onRotate: () => _rotateBy(45),
              onToggleWalk: () => _bitController.reportMovement(isMoving: true),
              onToggleIdle: () =>
                  _bitController.reportMovement(isMoving: false),
              sceneLabel: _loadedReplayLabel ?? _scene.label,
              onNextScene: _nextScene,
              onOpenReplay: _openReplay,
              passLabel: _passPreset.label,
              onNextPass: _nextPassPreset,
              benchmarkRunning: _benchmarkRunning,
              onRunBenchmark: _runBenchmark,
              layerSweepRunning: _layerSweepRunning,
              onRunLayerSweep: _runLayerSweep,
              diagnosticsVisible: _showDiagnostics,
              onToggleDiagnostics: () =>
                  setState(() => _showDiagnostics = !_showDiagnostics),
            ),
          ),
          if (_showDiagnostics)
            Positioned(
              left: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              // The readout itself changes several times per second. Keep it
              // in its own paint subtree: otherwise the profiler becomes a
              // source of full-map repaints and measures its own overhead.
              child: RepaintBoundary(
                child: ValueListenableBuilder<MapFrameStats>(
                  valueListenable: _frameMonitor.stats,
                  builder: (context, stats, _) => _ProfileStatsCard(
                    stats: stats,
                    scene: MapSceneMetrics.fromFeatures(_features),
                    quality: MapRenderingBudget.decorativeQuality,
                    pressure: MapRenderingBudget.framePressureLevel,
                    benchmarkStats: _lastBenchmarkStats,
                    benchmarkScene: _lastBenchmarkScene,
                    layerBenchmarkStats: _layerBenchmarkStats,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ProfileScene {
  standard('Scena standard'),
  osmReplay('Replay OSM'),
  stress('Scena stress');

  const _ProfileScene(this.label);

  final String label;

  MapFeatureCollection get features => switch (this) {
    _ProfileScene.standard => mixedPreviewFeatures,
    _ProfileScene.osmReplay => osmReplayFeatures,
    _ProfileScene.stress => rendererStressFeatures,
  };
}

/// Comparable groups of the production compositor.  These presets exist only
/// in the local profiling target: they do not alter release map evidence.
enum _ProfilePassPreset {
  full('Tutti i layer'),
  base('Base'),
  hydrology('Idrologia'),
  terrain('Terreno'),
  routes('Percorsi'),
  vegetation('Vegetazione'),
  poiUrban('POI e urbano');

  const _ProfilePassPreset(this.label);

  final String label;

  bool get drawTerrainBase =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.base;
  bool get drawCoastline =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.hydrology;
  bool get drawWater =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.hydrology;
  bool get drawBiome =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.terrain;
  bool get drawGeology =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.terrain;
  bool get drawContours =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.terrain;
  bool get drawRoutes =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.routes;
  bool get drawUrban =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.poiUrban;
  bool get drawVegetation =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.vegetation;
  bool get drawPois =>
      this == _ProfilePassPreset.full || this == _ProfilePassPreset.poiUrban;
}

class _ProfileBitActor extends StatelessWidget {
  const _ProfileBitActor({required this.position, required this.controller});

  final LatLng position;
  final BitAnimationController controller;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final pixelSize = (32 * (camera.zoom / 16)).clamp(18.0, 46.0).toDouble();
    final offset = camera.latLngToScreenOffset(position);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: offset.dx - pixelSize / 2,
            top: offset.dy - pixelSize * 1.5,
            child: BitCursor(controller: controller, pixelSize: pixelSize),
          ),
        ],
      ),
    );
  }
}

class _ProfileToolbar extends StatelessWidget {
  const _ProfileToolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRotate,
    required this.onToggleWalk,
    required this.onToggleIdle,
    required this.sceneLabel,
    required this.onNextScene,
    required this.onOpenReplay,
    required this.passLabel,
    required this.onNextPass,
    required this.benchmarkRunning,
    required this.onRunBenchmark,
    required this.layerSweepRunning,
    required this.onRunLayerSweep,
    required this.diagnosticsVisible,
    required this.onToggleDiagnostics,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRotate;
  final VoidCallback onToggleWalk;
  final VoidCallback onToggleIdle;
  final String sceneLabel;
  final VoidCallback onNextScene;
  final Future<void> Function() onOpenReplay;
  final String passLabel;
  final VoidCallback onNextPass;
  final bool benchmarkRunning;
  final VoidCallback onRunBenchmark;
  final bool layerSweepRunning;
  final VoidCallback onRunLayerSweep;
  final bool diagnosticsVisible;
  final VoidCallback onToggleDiagnostics;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xE6142A25),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Renderer profile locale'),
          IconButton(
            tooltip: 'Zoom indietro',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Zoom avanti',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Ruota 45°',
            onPressed: onRotate,
            icon: const Icon(Icons.rotate_right),
          ),
          TextButton(onPressed: onToggleIdle, child: const Text('Bit fermo')),
          TextButton(onPressed: onToggleWalk, child: const Text('Bit cammina')),
          TextButton(onPressed: onNextScene, child: Text(sceneLabel)),
          TextButton(onPressed: onNextPass, child: Text(passLabel)),
          IconButton(
            tooltip: 'Apri replay locale',
            onPressed: onOpenReplay,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: benchmarkRunning
                ? 'Benchmark renderer in corso'
                : 'Esegui benchmark renderer',
            onPressed: benchmarkRunning ? null : onRunBenchmark,
            icon: Icon(benchmarkRunning ? Icons.timer : Icons.timer_outlined),
          ),
          IconButton(
            tooltip: layerSweepRunning
                ? 'Profilo per layer in corso'
                : 'Esegui profilo per layer',
            onPressed: benchmarkRunning || layerSweepRunning
                ? null
                : onRunLayerSweep,
            icon: Icon(
              layerSweepRunning
                  ? Icons.playlist_play
                  : Icons.playlist_add_check_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Metriche',
            onPressed: onToggleDiagnostics,
            icon: Icon(
              diagnosticsVisible ? Icons.insights : Icons.insights_outlined,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileStatsCard extends StatelessWidget {
  const _ProfileStatsCard({
    required this.stats,
    required this.scene,
    required this.quality,
    required this.pressure,
    required this.benchmarkStats,
    required this.benchmarkScene,
    required this.layerBenchmarkStats,
  });

  final MapFrameStats stats;
  final MapSceneMetrics scene;
  final double quality;
  final int pressure;
  final MapFrameStats? benchmarkStats;
  final String? benchmarkScene;
  final Map<_ProfilePassPreset, MapFrameStats> layerBenchmarkStats;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xE6142A25),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        'Profilo locale · ${stats.sampleCount}/60 frame\n'
        'build ${_millis(stats.averageBuildMicros)} ms · '
        'raster ${_millis(stats.averageRasterMicros)} ms\n'
        'p95 ${_millis(stats.p95FrameMicros)} ms · '
        'peggiore ${_millis(stats.worstFrameMicros)} ms · '
        'lenti ${(stats.slowFrameRate * 100).toStringAsFixed(0)}%\n'
        'dettaglio ${(quality * 100).round()}% · pressione $pressure\n'
        'scena ${scene.loadBand}: ${scene.areaCount} aree · '
        '${scene.lineCount} vie · ${scene.poiCount} POI\n'
        '${scene.totalVertices} vertici · ${scene.trails} sentieri · '
        '${scene.waterAreas} acqua · ${scene.trees} alberi'
        '${_benchmarkLine()}${_layerSweepLine()}',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
  );

  String _millis(int micros) => (micros / 1000).toStringAsFixed(1);

  String _benchmarkLine() {
    final result = benchmarkStats;
    if (result == null) return '';
    return '\nultimo benchmark ${benchmarkScene ?? 'locale'} · '
        'p95 ${_millis(result.p95FrameMicros)} ms · '
        'lenti ${(result.slowFrameRate * 100).toStringAsFixed(0)}%';
  }

  String _layerSweepLine() {
    if (layerBenchmarkStats.isEmpty) return '';
    final entries = _ProfilePassPreset.values
        .where(layerBenchmarkStats.containsKey)
        .map(
          (pass) =>
              '${pass.label}: '
              '${_millis(layerBenchmarkStats[pass]!.p95FrameMicros)}',
        );
    return '\nlayer p95 ms · ${entries.join(' · ')}';
  }
}
