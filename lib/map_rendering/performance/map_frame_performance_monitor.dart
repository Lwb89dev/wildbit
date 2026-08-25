import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A compact rolling snapshot of the work Flutter spent building and
/// rasterising recent frames.
@immutable
class MapFrameStats {
  const MapFrameStats({
    required this.sampleCount,
    required this.slowFrameCount,
    required this.averageBuildMicros,
    required this.averageRasterMicros,
    required this.worstFrameMicros,
  });

  const MapFrameStats.empty()
    : sampleCount = 0,
      slowFrameCount = 0,
      averageBuildMicros = 0,
      averageRasterMicros = 0,
      worstFrameMicros = 0;

  final int sampleCount;
  final int slowFrameCount;
  final int averageBuildMicros;
  final int averageRasterMicros;
  final int worstFrameMicros;

  double get slowFrameRate =>
      sampleCount == 0 ? 0 : slowFrameCount / sampleCount;

  bool get overBudget => slowFrameCount > 0;
}

/// Collects frame timings without doing work in the map's paint callbacks.
///
/// The rolling window bounds memory and keeps the debug signal useful when a
/// single expensive Overpass response or a one-off shader compilation occurs.
/// The monitor is deliberately opt-in: production builds can leave it stopped
/// so it has no battery or frame-time cost.
class MapFramePerformanceMonitor {
  MapFramePerformanceMonitor({
    this.targetFrameMicros = 16667,
    this.windowSize = 60,
  }) : assert(targetFrameMicros > 0),
       assert(windowSize > 0);

  final int targetFrameMicros;
  final int windowSize;
  final ValueNotifier<MapFrameStats> stats = ValueNotifier<MapFrameStats>(
    const MapFrameStats.empty(),
  );
  final List<_FrameSample> _samples = <_FrameSample>[];
  bool _running = false;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_running) return;
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _running = false;
  }

  void dispose() {
    stop();
    stats.dispose();
  }

  /// Records a pair directly for deterministic tests and local profiling.
  /// Frame callbacks use the same path, so reported values match Flutter's
  /// actual build/raster timings.
  void recordDurations(Duration build, Duration raster) {
    final buildMicros = build.inMicroseconds;
    final rasterMicros = raster.inMicroseconds;
    _samples.add(_FrameSample(buildMicros, rasterMicros));
    if (_samples.length > windowSize) {
      _samples.removeRange(0, _samples.length - windowSize);
    }
    _publish();
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      recordDurations(timing.buildDuration, timing.rasterDuration);
    }
  }

  void _publish() {
    if (_samples.isEmpty) {
      stats.value = const MapFrameStats.empty();
      return;
    }
    var buildTotal = 0;
    var rasterTotal = 0;
    var worst = 0;
    var slow = 0;
    for (final sample in _samples) {
      buildTotal += sample.buildMicros;
      rasterTotal += sample.rasterMicros;
      // Build and raster run in different Flutter stages/threads. A frame is
      // over budget when either stage exceeds the target, not when their
      // durations are added together.
      final frameMicros = sample.buildMicros > sample.rasterMicros
          ? sample.buildMicros
          : sample.rasterMicros;
      if (frameMicros > worst) worst = frameMicros;
      if (frameMicros > targetFrameMicros) slow++;
    }
    stats.value = MapFrameStats(
      sampleCount: _samples.length,
      slowFrameCount: slow,
      averageBuildMicros: (buildTotal / _samples.length).round(),
      averageRasterMicros: (rasterTotal / _samples.length).round(),
      worstFrameMicros: worst,
    );
  }

  @visibleForTesting
  void clear() {
    _samples.clear();
    _publish();
  }
}

class _FrameSample {
  const _FrameSample(this.buildMicros, this.rasterMicros);

  final int buildMicros;
  final int rasterMicros;
}
