import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../domain/entities/area_feature.dart';
import '../../domain/entities/line_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';

/// An illustrated topographic map renderer.  It deliberately paints at the
/// display resolution: geographic shapes retain their natural contours while
/// small, layered details give the map the depth of a modern 2D adventure.
class HdTerrainPainter extends CustomPainter {
  HdTerrainPainter({
    required this.camera,
    required this.features,
    this.isDark = false,
    this.paintBase = true,
    this.paintWater = true,
    this.paintAreas = true,
    this.paintLines = true,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final bool isDark;
  final bool paintBase;
  final bool paintWater;
  final bool paintAreas;
  final bool paintLines;

  static const _forest = Color(0xFF315C45);
  static const _meadow = Color(0xFF9BB867);
  static const _water = Color(0xFF3987A3);
  static const _rock = Color(0xFF8D8173);
  static const _snow = Color(0xFFF4F0E6);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (paintBase) _paintBase(canvas, size);
    if (paintAreas) {
      for (final area in features.areas) {
        _paintArea(canvas, area, size);
      }
    }
    if (paintLines) {
      for (final line in features.lines) {
        _paintLine(canvas, line, size);
      }
    }
    _paintAtmosphere(canvas, size);
  }

  void _paintBase(Canvas canvas, Size size) {
    final base = isDark
        ? const [Color(0xFF172820), Color(0xFF273D2A)]
        : const [Color(0xFFC9D59A), Color(0xFF91B476)];
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: base,
        ).createShader(Offset.zero & size),
    );

    // A restrained 64-bit pixel texture: it breaks the otherwise perfectly
    // smooth vector fill into authored-looking terrain cells while preserving
    // the geographic precision of the paths painted above it.
    final cell = camera.zoom >= 14 ? 8.0 : 12.0;
    final light = isDark ? const Color(0xFF3E684A) : const Color(0xFFBDD087);
    final shade = isDark ? const Color(0xFF1E3427) : const Color(0xFF789A61);
    final sparkle = isDark ? const Color(0xFF63836A) : const Color(0xFFD8E3A6);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final seed = (x ~/ cell * 17 + y ~/ cell * 31) % 19;
        if (seed == 0 || seed == 7 || seed == 13) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, cell, cell),
            Paint()
              ..color =
                  (seed == 0
                          ? sparkle
                          : seed == 7
                          ? shade
                          : light)
                      .withValues(alpha: .14),
          );
        }
      }
    }

    // Subtle contour curves make the empty portions of the viewport feel like
    // land rather than a flat background, without competing with real data.
    final contourPaint = Paint()
      ..color = (isDark ? const Color(0xFF9BBE88) : const Color(0xFF55764A))
          .withValues(alpha: isDark ? 0.11 : 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..isAntiAlias = false;
    for (var y = -30.0; y < size.height + 45; y += 48) {
      final path = Path()..moveTo(-20, y);
      for (var x = 0.0; x <= size.width + 30; x += 30) {
        final wave = math.sin((x + y * 0.55) / 58) * 5 + math.sin(x / 21) * 1.8;
        path.lineTo(x, y + wave);
      }
      canvas.drawPath(path, contourPaint);
    }
  }

  void _paintArea(Canvas canvas, AreaFeature area, Size size) {
    if (area.ring.isEmpty || !_pointsMayBeVisible(area.ring)) return;
    final path = _pathFor(area.ring);
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    final visibleBounds = bounds.intersect(Offset.zero & size);
    if (visibleBounds.isEmpty) return;

    switch (area.kind) {
      case MapFeatureKind.forest:
        _paintForest(canvas, path, bounds, visibleBounds);
      case MapFeatureKind.meadow:
        _paintMeadow(canvas, path, bounds, visibleBounds);
      case MapFeatureKind.water:
        if (paintWater) _paintWater(canvas, path, bounds, visibleBounds);
      case MapFeatureKind.mountainRock:
        _paintMountain(canvas, path, bounds, visibleBounds);
      case MapFeatureKind.snow:
        _paintSnow(canvas, path, bounds, visibleBounds);
      default:
        _paintGenericArea(canvas, path, bounds);
    }
  }

  Path _pathFor(List<LatLng> points) {
    final path = Path();
    final first = camera.latLngToScreenOffset(points.first);
    path.moveTo(first.dx, first.dy);
    for (final point in points.skip(1)) {
      final offset = camera.latLngToScreenOffset(point);
      path.lineTo(offset.dx, offset.dy);
    }
    return path..close();
  }

  bool _pointsMayBeVisible(List<LatLng> points) {
    final view = camera.visibleBounds;
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    // A small geographic margin prevents features at the edge from popping.
    const margin = .002;
    return maxLat >= view.south - margin &&
        minLat <= view.north + margin &&
        maxLng >= view.west - margin &&
        minLng <= view.east + margin;
  }

  void _paintForest(Canvas canvas, Path path, Rect bounds, Rect visibleBounds) {
    _fillAndEdge(canvas, path, bounds, const [
      _forest,
      Color(0xFF1F4939),
    ], const Color(0xFF174131));
    canvas.save();
    canvas.clipPath(path);
    if (_showDetails) {
      final spacing = _cappedSpacing(
        visibleBounds,
        preferred: _detailSpacing(28, 72),
        maxItems: 42,
      );
      for (
        var y = visibleBounds.top - spacing;
        y < visibleBounds.bottom + spacing;
        y += spacing
      ) {
        for (
          var x = visibleBounds.left - spacing;
          x < visibleBounds.right + spacing;
          x += spacing
        ) {
          final wobble = math.sin(x * .07 + y * .13) * spacing * .24;
          _paintTree(canvas, Offset(x + wobble, y), spacing * .38);
        }
      }
    }
    canvas.restore();
  }

  void _paintTree(Canvas canvas, Offset center, double radius) {
    final shadow = Paint()
      ..color = const Color(0xFF153829).withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(radius * .22, radius * .4),
        width: radius * 1.7,
        height: radius * .72,
      ),
      shadow,
    );
    final crown = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.3, -.6),
        radius: 1,
        colors: [const Color(0xFF70A76B), const Color(0xFF285A43)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, crown);
    canvas.drawCircle(
      center - Offset(radius * .3, radius * .35),
      radius * .38,
      Paint()..color = const Color(0xFFB7D38A).withValues(alpha: .34),
    );
  }

  void _paintMeadow(Canvas canvas, Path path, Rect bounds, Rect visibleBounds) {
    _fillAndEdge(canvas, path, bounds, const [
      _meadow,
      Color(0xFF779D58),
    ], const Color(0xFF628848));
    canvas.save();
    canvas.clipPath(path);
    final grass = Paint()
      ..color = const Color(0xFFD7E49A).withValues(alpha: .32)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    if (_showDetails) {
      final stride = _cappedSpacing(
        visibleBounds,
        preferred: _detailSpacing(24, 58),
        maxItems: 64,
      );
      for (var y = visibleBounds.top; y < visibleBounds.bottom; y += stride) {
        for (var x = visibleBounds.left; x < visibleBounds.right; x += stride) {
          final tilt = math.sin(x * .12 + y * .08) * 3;
          canvas.drawLine(Offset(x, y + 5), Offset(x + tilt, y - 3), grass);
        }
      }
    }
    canvas.restore();
  }

  void _paintWater(Canvas canvas, Path path, Rect bounds, Rect visibleBounds) {
    _fillAndEdge(canvas, path, bounds, const [
      _water,
      Color(0xFF236B8C),
    ], const Color(0xFF1C5671));
    canvas.save();
    canvas.clipPath(path);
    final ripple = Paint()
      ..color = const Color(0xFFD4F0E9).withValues(alpha: isDark ? .18 : .38)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (_showDetails) {
      final spacing = _cappedSpacing(
        visibleBounds,
        preferred: _detailSpacing(28, 68),
        maxItems: 36,
      );
      for (
        var y = visibleBounds.top + spacing * .4;
        y < visibleBounds.bottom;
        y += spacing
      ) {
        for (
          var x = visibleBounds.left - spacing;
          x < visibleBounds.right;
          x += spacing * 1.55
        ) {
          final width = spacing * (.52 + .18 * math.sin((x + y) * .12));
          canvas.drawArc(
            Rect.fromLTWH(x, y, width, 6),
            0.15,
            math.pi - .3,
            false,
            ripple,
          );
        }
      }
    }
    canvas.restore();
  }

  void _paintMountain(
    Canvas canvas,
    Path path,
    Rect bounds,
    Rect visibleBounds,
  ) {
    _fillAndEdge(canvas, path, bounds, const [
      _rock,
      Color(0xFF625E59),
    ], const Color(0xFF554E49));
    canvas.save();
    canvas.clipPath(path);
    final facet = Paint()
      ..color = const Color(0xFFC0B4A0).withValues(alpha: .28);
    final shadow = Paint()
      ..color = const Color(0xFF403F42).withValues(alpha: .3);
    if (_showDetails) {
      final span = _cappedSpacing(
        visibleBounds,
        preferred: _detailSpacing(68, 150),
        maxItems: 20,
      );
      for (
        var y = visibleBounds.top - span;
        y < visibleBounds.bottom + span;
        y += span * .72
      ) {
        for (
          var x = visibleBounds.left - span;
          x < visibleBounds.right + span;
          x += span
        ) {
          final peak = Offset(x + span * .5, y);
          canvas.drawPath(
            Path()
              ..moveTo(peak.dx, peak.dy)
              ..lineTo(x, y + span)
              ..lineTo(x + span * .52, y + span * .7)
              ..close(),
            facet,
          );
          canvas.drawPath(
            Path()
              ..moveTo(peak.dx, peak.dy)
              ..lineTo(x + span * .52, y + span * .7)
              ..lineTo(x + span, y + span)
              ..close(),
            shadow,
          );
        }
      }
    }
    canvas.restore();
  }

  void _paintSnow(Canvas canvas, Path path, Rect bounds, Rect visibleBounds) {
    _fillAndEdge(canvas, path, bounds, const [
      _snow,
      Color(0xFFD8E0D9),
    ], const Color(0xFFBAC9C2));
    canvas.save();
    canvas.clipPath(path);
    final sheen = Paint()..color = Colors.white.withValues(alpha: .62);
    if (_showDetails) {
      final spacing = _cappedSpacing(
        visibleBounds,
        preferred: _detailSpacing(20, 48),
        maxItems: 16,
      );
      for (var y = visibleBounds.top; y < visibleBounds.bottom; y += spacing) {
        canvas.drawOval(
          Rect.fromLTWH(visibleBounds.left, y, visibleBounds.width * .66, 2.2),
          sheen,
        );
      }
    }
    canvas.restore();
  }

  void _paintGenericArea(Canvas canvas, Path path, Rect bounds) {
    _fillAndEdge(canvas, path, bounds, const [
      Color(0xFF95AA75),
      Color(0xFF6D885C),
    ], const Color(0xFF536F48));
  }

  void _fillAndEdge(
    Canvas canvas,
    Path path,
    Rect bounds,
    List<Color> colors,
    Color edge,
  ) {
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: isDark ? .22 : .11),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.map((color) => isDark ? _dim(color) : color).toList(),
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = edge.withValues(alpha: isDark ? .8 : .72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..isAntiAlias = false,
    );
  }

  void _paintLine(Canvas canvas, LineFeature line, Size size) {
    if (line.points.length < 2 || !_pointsMayBeVisible(line.points)) return;
    final path = Path();
    final first = camera.latLngToScreenOffset(line.points.first);
    path.moveTo(first.dx, first.dy);
    for (final point in line.points.skip(1)) {
      final offset = camera.latLngToScreenOffset(point);
      path.lineTo(offset.dx, offset.dy);
    }

    if (!path.getBounds().overlaps(Offset.zero & size)) return;
    switch (line.kind) {
      case MapFeatureKind.trail:
        _paintTrail(canvas, path);
      case MapFeatureKind.road:
        _paintRoad(canvas, path);
      default:
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF64735D).withValues(alpha: .7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
    }
  }

  void _paintTrail(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4B3827).withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = isDark ? const Color(0xFFD7AE62) : const Color(0xFFE8C779)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintRoad(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4A4942).withValues(alpha: .48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = isDark ? const Color(0xFF908D81) : const Color(0xFFE1D8C6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFAF9D79).withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintAtmosphere(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: .88,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: isDark ? .27 : .1),
        ],
        stops: const [.62, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  bool get _showDetails => camera.zoom >= 13.5;

  double _detailSpacing(double min, double max) =>
      ((18 - camera.zoom) * 7 + min).clamp(min, max);

  double _cappedSpacing(
    Rect bounds, {
    required double preferred,
    required int maxItems,
  }) {
    final requiredForBudget = math.sqrt(
      bounds.width * bounds.height / maxItems,
    );
    return math.max(preferred, requiredForBudget);
  }

  Color _dim(Color color) => Color.lerp(color, const Color(0xFF122018), .38)!;

  @override
  bool shouldRepaint(covariant HdTerrainPainter oldDelegate) {
    return oldDelegate.camera.center != camera.center ||
        oldDelegate.camera.zoom != camera.zoom ||
        oldDelegate.camera.rotation != camera.rotation ||
        oldDelegate.isDark != isDark ||
        oldDelegate.paintBase != paintBase ||
        oldDelegate.paintWater != paintWater ||
        oldDelegate.paintAreas != paintAreas ||
        oldDelegate.paintLines != paintLines ||
        oldDelegate.features != features;
  }
}
