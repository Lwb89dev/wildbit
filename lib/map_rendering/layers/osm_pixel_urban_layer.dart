import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../domain/entities/area_feature.dart';
import '../../domain/entities/map_feature_collection.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../performance/map_rendering_budget.dart';

/// A deliberately quiet urban backdrop. Buildings provide orientation without
/// turning the map into a grey raster block or competing with trails.
class OsmPixelUrbanLayer extends StatelessWidget {
  const OsmPixelUrbanLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final buildings = features.areas
        .where(
          (area) =>
              area.kind == MapFeatureKind.building &&
              MapRenderingBudget.areaMayBeVisible(area, camera.visibleBounds),
        )
        .toList(growable: false)
      ..sort((a, b) => _centroidLatitude(b).compareTo(_centroidLatitude(a)));
    if (buildings.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: CustomPaint(
            painter: _UrbanPainter(camera: camera, buildings: buildings),
          ),
        ),
      ),
    );
  }

  static double _centroidLatitude(AreaFeature area) {
    if (area.ring.isEmpty) return 0;
    return area.ring
            .map((point) => point.latitude)
            .reduce((a, b) => a + b) /
        area.ring.length;
  }
}

class _UrbanPainter extends CustomPainter {
  const _UrbanPainter({required this.camera, required this.buildings});

  final MapCamera camera;
  final List<AreaFeature> buildings;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = MapRenderingBudget.decorativeScale(
      camera.zoom,
      min: .35,
      max: 1.1,
    );
    final detail = ((camera.zoom - 12) / 3).clamp(0.0, 1.0);
    final extrusion = (1.5 + 2.5 * detail) * scale;
    for (final area in buildings) {
      final ring = area.ring;
      if (ring.length < 3) continue;
      final raw = [
        for (final point in ring) camera.latLngToScreenOffset(point),
      ];
      // Snap the polygon as one rigid object. Snapping every vertex
      // independently changed its silhouette at fractional zoom values.
      final snapDelta = _snap(raw.first) - raw.first;
      final projected = [for (final point in raw) point + snapDelta];
      final roof = _path(projected);
      final wall = _path([
        for (final point in projected) point.translate(0, extrusion),
      ]);
      canvas.drawPath(
        wall.shift(Offset(2 * scale, 2 * scale)),
        Paint()
          ..color = const Color(0x55312624)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        wall,
        Paint()
          ..color = const Color(0xFF6F5542)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        roof,
        Paint()
          ..color = const Color(0xFF8D694C)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        roof,
        Paint()
          ..color = const Color(0xFF3B302A)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              1 + .4 * ((camera.zoom - 11) / 5).clamp(0.0, 1.0),
      );
      if (detail > 0) {
        _paintRoofInset(canvas, projected, detail);
      }
    }
  }

  Offset _snap(Offset point) =>
      Offset(point.dx.roundToDouble(), point.dy.roundToDouble());

  Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  void _paintRoofInset(
    Canvas canvas,
    List<Offset> projected,
    double detail,
  ) {
    if (projected.length < 3) return;
    var center = Offset.zero;
    for (final point in projected) {
      center += point;
    }
    center /= projected.length.toDouble();
    final inset = Path();
    for (var i = 0; i < projected.length; i++) {
      final point = Offset.lerp(center, projected[i], .78)!;
      if (i == 0) {
        inset.moveTo(point.dx, point.dy);
      } else {
        inset.lineTo(point.dx, point.dy);
      }
    }
    inset.close();
    canvas.drawPath(
      inset,
      Paint()
        ..color = const Color(0xFF3E3934).withValues(alpha: .4 * detail)
        ..style = PaintingStyle.fill,
    );
    final highlightStrength = ((camera.zoom - 12) / 4).clamp(0.0, 1.0);
    if (highlightStrength <= 0) return;
    final highlight = Paint()
      ..color = const Color(0xFF403A34).withValues(
        alpha: .33 * highlightStrength,
      )
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < projected.length; i += 2) {
      canvas.drawLine(projected[i], projected[i + 1], highlight);
    }
  }

  @override
  bool shouldRepaint(_UrbanPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.buildings != buildings;
}
