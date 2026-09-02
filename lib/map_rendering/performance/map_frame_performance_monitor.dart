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
    required this.p95FrameMicros,
    required this.worstFrameMicros,
  });

  const MapFrameStats.empty()
    : sampleCount = 0,
      slowFrameCount = 0,
      averageBuildMicros = 0,
      averageRasterMicros = 0,
      p95FrameMicros = 0,
      worstFrameMicros = 0;

  final int sampleCount;
  final int slowFrameCount;
  final int averageBuildMicros;
  final int averageRasterMicros;

  /// 95th percentile of the slower between build and raster for each frame.
  /// Unlike [worstFrameMicros], this is resilient to one-off shader warm-up.
  final int p95FrameMicros;
  final int worstFrameMicros;

  double get slowFrameRate =>
      sampleCount == 0 ? 0 : slowFrameCount / sampleCount;

  bool get overBudget => slowFrameCount > 0;
}

/// Collects frame timings without doing work in the map's paint callbacks.
///
/// The rolling window bounds memory and keeps the debug signal useful when a
/// single expensive Overpass response or a one-off shader compilation occurs.
/// The monitor itself is intentionally compact: production builds use the
/// rolling signal only to select a safer decorative tier, while the diagnostic
/// panel remains debug/profile-only.
class MapFramePerformanceMonitor {
  MapFramePerformanceMonitor({
    this.targetFrameMicros = 16667,
    this.windowSize = 60,
    this.publishEvery = 4,
  }) : assert(targetFrameMicros > 0),
       assert(windowSize > 0),
       assert(publishEvery > 0);

  final int targetFrameMicros;
  final int windowSize;

  /// Number of samples collected before notifying listeners. Frame timings
  /// are still retained individually; throttling only avoids a Dart rebuild
  /// and quality-budget decision on every display refresh.
  final int publishEvery;
  final ValueNotifier<MapFrameStats> stats = ValueNotifier<MapFrameStats>(
    const MapFrameStats.empty(),
  );
  final List<_FrameSample> _samples = <_FrameSample>[];
  int _pendingPublications = 0;
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
    _pendingPublications++;
    if (_pendingPublications >= publishEvery) {
      _pendingPublications = 0;
      _publish();
    }
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
    final frameSamples = <int>[];
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
      frameSamples.add(frameMicros);
    }
    frameSamples.sort();
    final p95Index = ((frameSamples.length - 1) * .95).ceil();
    stats.value = MapFrameStats(
      sampleCount: _samples.length,
      slowFrameCount: slow,
      averageBuildMicros: (buildTotal / _samples.length).round(),
      averageRasterMicros: (rasterTotal / _samples.length).round(),
      p95FrameMicros: frameSamples[p95Index],
      worstFrameMicros: worst,
    );
  }

  /// Starts a fresh measurement window without unregistering the timing hook.
  /// Used by the local renderer benchmark before its scripted camera gesture.
  void reset() {
    _samples.clear();
    _pendingPublications = 0;
    _publish();
  }

  /// Publishes the current rolling window immediately. A scripted benchmark
  /// uses this at its end so its result is not delayed by [publishEvery].
  void flush() {
    _pendingPublications = 0;
    _publish();
  }

  @visibleForTesting
  void clear() => reset();
}

class _FrameSample {
  const _FrameSample(this.buildMicros, this.rasterMicros);

  final int buildMicros;
  final int rasterMicros;
}
