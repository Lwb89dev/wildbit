import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../../domain/entities/weather_snapshot.dart';
import '../../services/weather/weather_service.dart';
import '../composition/pan_projection_frame.dart';
import '../performance/map_rendering_budget.dart';

/// Screen-space weather effects. It is deliberately one painter and one
/// repaint boundary: a rain drop is not a widget and never participates in
/// layout or hit testing.
class WeatherOverlay extends StatelessWidget {
  const WeatherOverlay({super.key, required this.weather});

  final WeatherService weather;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        final snapshot = weather.snapshot;
        if (snapshot == null) return const SizedBox.expand();
        final isAnimated =
            snapshot.isRain ||
            snapshot.isSnow ||
            snapshot.isStorm ||
            snapshot.fogIntensity > .05 ||
            !snapshot.isDay;
        Widget paint(double phase) => CustomPaint(
          painter: WeatherOverlayPainter(
            snapshot: snapshot,
            phase: phase,
            quality: MapRenderingBudget.decorativeQuality,
          ),
        );
        return RepaintBoundary(
          child: IgnorePointer(
            child: isAnimated
                ? AnimatedBuilder(
                    animation: MapRenderingBudget.ambientClock,
                    builder: (context, _) =>
                        paint(MapRenderingBudget.ambientClock.phase),
                  )
                : paint(0),
          ),
        );
      },
    );
  }
}

/// Geographic shadow pass, inserted below OSM objects but above the terrain.
/// Only mapped building footprints are shadowed here; trees and rocks already
/// have grounding shadows in their sprite painter. At lower quality levels
/// the number of footprints is capped instead of removing map evidence.
class WeatherShadowLayer extends StatefulWidget {
  const WeatherShadowLayer({
    super.key,
    required this.features,
    required this.weather,
  });

  final MapFeatureCollection features;
  final WeatherService weather;

  @override
  State<WeatherShadowLayer> createState() => _WeatherShadowLayerState();
}

class _WeatherShadowLayerState extends State<WeatherShadowLayer> {
  MapFeatureCollection? _source;
  List<AreaFeature> _buildings = const [];
  // Footprint outlines projected into the current pan frame.
  PanProjectionFrame? _frame;
  final Map<AreaFeature, ui.Path> _framePaths = {};

  List<AreaFeature> _sourceBuildings() {
    if (identical(_source, widget.features)) return _buildings;
    _source = widget.features;
    _framePaths.clear();
    return _buildings = List.unmodifiable([
      for (final area in widget.features.areas)
        if (area.kind == MapFeatureKind.building && area.ring.length >= 3) area,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return ListenableBuilder(
      listenable: widget.weather,
      builder: (context, _) {
        final snapshot = widget.weather.snapshot;
        if (snapshot == null || !snapshot.isDay || snapshot.directLight < .14) {
          return const SizedBox.expand();
        }
        final frame = _frame;
        if (frame == null || !frame.accepts(camera)) {
          _frame = PanProjectionFrame(camera);
          _framePaths.clear();
        }
        final offset = _frame!.offsetFor(camera);
        final quality = MapRenderingBudget.decorativeQuality;
        // Cap the buildings actually in view; the first footprints of the
        // whole collection used to take the budget even when off-screen.
        final limit = (70 * quality.clamp(.3, 1.0)).round();
        final paths = <ui.Path>[];
        for (final building in _sourceBuildings()) {
          if (paths.length >= limit) break;
          if (!MapRenderingBudget.areaMayBeVisible(
            building,
            camera.visibleBounds,
          )) {
            continue;
          }
          paths.add(
            _framePaths[building] ??= _footprintPath(
              building.ring,
              camera,
              offset,
            ),
          );
        }
        if (paths.isEmpty) return const SizedBox.expand();
        return IgnorePointer(
          child: CustomPaint(
            painter: WeatherShadowPainter(
              offset: offset,
              footprints: paths,
              snapshot: snapshot,
              quality: quality,
            ),
          ),
        );
      },
    );
  }

  static ui.Path _footprintPath(
    List<LatLng> ring,
    MapCamera camera,
    Offset offset,
  ) {
    final path = ui.Path();
    for (var index = 0; index < ring.length; index++) {
      final point = PanProjectionFrame.project(camera, offset, ring[index]);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }
}

class WeatherOverlayPainter extends CustomPainter {
  const WeatherOverlayPainter({
    required this.snapshot,
    required this.phase,
    required this.quality,
  });

  final WeatherSnapshot snapshot;
  final double phase;
  final double quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final q = quality.clamp(.3, 1.0).toDouble();
    _paintTint(canvas, size);
    _paintDynamicLights(canvas, size, q);
    _paintFog(canvas, size, q);
    _paintRain(canvas, size, q);
    _paintSnow(canvas, size, q);
    if (snapshot.isStorm) _paintLightning(canvas, size);
  }

  void _paintTint(Canvas canvas, Size size) {
    final cloud = snapshot.cloudIntensity;
    final weatherAlpha = snapshot.isStorm
        ? .12
        : snapshot.isSnow
        ? .055
        : snapshot.isRain
        ? .04
        : 0.0;
    final nightAlpha = snapshot.isDay ? 0.0 : .22;
    if (weatherAlpha == 0 && nightAlpha == 0 && cloud < .45) return;
    final color = snapshot.isDay
        ? const Color(0xFF6F8491)
        : const Color(0xFF14243A);
    final alpha = (nightAlpha + weatherAlpha + cloud * .045).clamp(0.0, .34);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  void _paintDynamicLights(Canvas canvas, Size size, double quality) {
    final night = !snapshot.isDay;
    final storm = snapshot.isStorm;
    if (!night && !storm) return;
    final count = (night ? 5 : 2) * quality;
    final lightPaint = Paint()..blendMode = BlendMode.plus;
    for (var index = 0; index < count.round(); index++) {
      final seed = index * 47.0 + 13;
      final center = Offset(
        (size.width * ((seed * .071) % 1.0)),
        (size.height * ((seed * .137) % 1.0)),
      );
      final pulse = .78 + .22 * math.sin((phase * math.pi * 2) + index);
      final radius = (night ? 28.0 : 20.0) * pulse;
      final color = storm ? const Color(0xFFBFD9FF) : const Color(0xFFFFC56B);
      lightPaint.shader = RadialGradient(
        colors: [
          color.withValues(alpha: .12 * pulse * quality),
          color.withValues(alpha: .025 * quality),
          Colors.transparent,
        ],
        stops: const [0, .35, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, lightPaint);
    }
    lightPaint.shader = null;
  }

  void _paintFog(Canvas canvas, Size size, double quality) {
    final intensity = snapshot.fogIntensity;
    if (intensity <= .05) return;
    final alpha = (.04 + intensity * .20) * quality;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: alpha * .72),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha * .55),
          ],
        ).createShader(Offset.zero & size),
    );

    // A few broad blurred banks provide depth without running a blur for
    // every particle. The pass disappears on the lowest quality tier.
    if (quality < .55) return;
    final blur = Paint()
      ..color = Colors.white.withValues(alpha: alpha * .6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * quality);
    for (var index = 0; index < 3; index++) {
      final y =
          size.height * (.22 + index * .31) +
          math.sin(phase * math.pi * 2 + index) * 12;
      canvas.drawRect(
        Rect.fromLTWH(-size.width * .1, y, size.width * 1.2, 20 + index * 5),
        blur,
      );
    }
  }

  void _paintRain(Canvas canvas, Size size, double quality) {
    if (!snapshot.isRain || snapshot.precipitationIntensity <= 0) return;
    final intensity = snapshot.precipitationIntensity;
    final count = (45 + intensity * 135) * quality;
    final paint = Paint()
      ..color = (snapshot.isDay ? const Color(0xFFB9D7E8) : Colors.white)
          .withValues(alpha: .24 + .14 * quality)
      ..strokeWidth = quality < .55 ? 1.0 : 1.25
      ..strokeCap = StrokeCap.square;
    final wind = (snapshot.windSpeedKmh / 80).clamp(-.35, .35).toDouble();
    for (var index = 0; index < count.round(); index++) {
      final seed = index * 83.17;
      final x =
          ((seed + phase * (size.width + 50) * (1 + wind)) %
              (size.width + 50)) -
          25;
      final y =
          ((seed * 1.73 + phase * (size.height + 80)) % (size.height + 80)) -
          40;
      final length = 7 + (seed % 9) * quality;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - 3 - wind * 14, y + length),
        paint,
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size, double quality) {
    if (!snapshot.isSnow || snapshot.snowIntensity <= 0) return;
    final intensity = snapshot.snowIntensity;
    final count = (35 + intensity * 105) * quality;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .56 + .16 * quality)
      ..isAntiAlias = false;
    for (var index = 0; index < count.round(); index++) {
      final seed = index * 61.37;
      final drift = math.sin(phase * math.pi * 2 + seed) * 18;
      final x = ((seed + drift) % (size.width + 24)) - 12;
      final y =
          ((seed * 1.41 + phase * (size.height + 30)) % (size.height + 30)) -
          15;
      final radius = 1.0 + (seed % 3) * .45 * quality;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final flash = math.max(0.0, math.sin(phase * math.pi * 2 * 2));
    if (flash < .96) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: .12 * flash),
    );
  }

  @override
  bool shouldRepaint(covariant WeatherOverlayPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.phase != phase ||
      oldDelegate.quality != quality;
}

class WeatherShadowPainter extends CustomPainter {
  const WeatherShadowPainter({
    required this.offset,
    required this.footprints,
    required this.snapshot,
    required this.quality,
  });

  /// Translation from the footprints' pan frame to the screen.
  final Offset offset;
  final List<ui.Path> footprints;
  final WeatherSnapshot snapshot;
  final double quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (footprints.isEmpty) return;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .075 * snapshot.directLight)
      ..isAntiAlias = false;
    final sunAngle = _sunAngle(snapshot.fetchedAt);
    final sunOffset = Offset(
      math.cos(sunAngle) * 11,
      math.sin(sunAngle) * 7 + 4,
    );
    canvas.save();
    canvas.translate(offset.dx + sunOffset.dx, offset.dy + sunOffset.dy);
    for (final footprint in footprints) {
      canvas.drawPath(footprint, shadow);
    }
    canvas.restore();
  }

  double _sunAngle(DateTime time) {
    final hour = time.toLocal().hour + time.toLocal().minute / 60;
    return ((hour - 6) / 12) * math.pi;
  }

  @override
  bool shouldRepaint(covariant WeatherShadowPainter oldDelegate) =>
      oldDelegate.offset != offset ||
      !listEquals(oldDelegate.footprints, footprints) ||
      oldDelegate.snapshot != snapshot ||
      oldDelegate.quality != quality;
}
