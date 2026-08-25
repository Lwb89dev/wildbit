import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/performance/map_frame_performance_monitor.dart';

void main() {
  test('publishes rolling build and raster frame statistics', () {
    final monitor = MapFramePerformanceMonitor(
      targetFrameMicros: 10,
      windowSize: 3,
    );
    addTearDown(monitor.dispose);

    monitor.recordDurations(
      const Duration(microseconds: 4),
      const Duration(microseconds: 5),
    );
    monitor.recordDurations(
      const Duration(microseconds: 8),
      const Duration(microseconds: 12),
    );

    expect(monitor.stats.value.sampleCount, 2);
    expect(monitor.stats.value.averageBuildMicros, 6);
    expect(monitor.stats.value.averageRasterMicros, 9);
    expect(monitor.stats.value.slowFrameCount, 1);
    expect(monitor.stats.value.worstFrameMicros, 12);
    expect(monitor.stats.value.slowFrameRate, .5);
    expect(monitor.stats.value.overBudget, isTrue);
  });

  test('keeps only the configured rolling window', () {
    final monitor = MapFramePerformanceMonitor(windowSize: 2);
    addTearDown(monitor.dispose);

    monitor.recordDurations(const Duration(microseconds: 100), Duration.zero);
    monitor.recordDurations(const Duration(microseconds: 20), Duration.zero);
    monitor.recordDurations(const Duration(microseconds: 40), Duration.zero);

    expect(monitor.stats.value.sampleCount, 2);
    expect(monitor.stats.value.averageBuildMicros, 30);
    expect(monitor.stats.value.worstFrameMicros, 40);
  });
}
