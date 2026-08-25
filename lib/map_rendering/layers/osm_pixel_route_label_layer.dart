import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/hiking_route_membership.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../composition/osm_line_projector.dart';
import '../composition/route_label_content.dart';
import '../composition/route_label_layout.dart';
import '../performance/map_rendering_budget.dart';

/// Labels mapped trail references and names without changing route geometry.
///
/// This is intentionally a separate late composition pass: terrain objects
/// may occlude Bit, but navigational labels must remain readable above them.
class OsmPixelRouteLabelLayer extends StatelessWidget {
  const OsmPixelRouteLabelLayer({
    super.key,
    required this.features,
    this.projectionCache,
  });

  final MapFeatureCollection features;
  final ProjectedLineCache? projectionCache;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final cache = projectionCache ?? ProjectedLineCache();
    cache.beginView(
      '${identityHashCode(features)}:${camera.center.latitude.toStringAsFixed(6)}:'
      '${camera.center.longitude.toStringAsFixed(6)}:'
      '${camera.zoom.toStringAsFixed(3)}:${camera.rotation.toStringAsFixed(2)}',
    );
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RouteLabelPainter(
            camera: camera,
            features: features,
            projectionCache: cache,
          ),
        ),
      ),
    );
  }
}

class _RouteLabelPainter extends CustomPainter {
  const _RouteLabelPainter({
    required this.camera,
    required this.features,
    required this.projectionCache,
  });

  final MapCamera camera;
  final MapFeatureCollection features;
  final ProjectedLineCache projectionCache;

  @override
  void paint(Canvas canvas, Size size) {
    final visuals = <String, _RouteLabelVisual>{};
    final candidates = <RouteLabelCandidate>[];
    for (final line in features.lines) {
      if (line.kind != MapFeatureKind.trail ||
          !MapRenderingBudget.lineMayBeVisible(line, camera.visibleBounds)) {
        continue;
      }
      final content = RouteLabelContent.forLine(line, camera.zoom);
      if (content == null) continue;

      final points = projectionCache.project(
        line,
        camera.latLngToScreenOffset,
        minimumDistancePixels: MapRenderingBudget.routePointDistancePixels(
          line,
          camera.zoom,
        ),
        maximumPoints: MapRenderingBudget.routeMaximumPoints(line, camera.zoom),
      );
      if (!OsmLineProjector.overlapsViewport(points, size)) continue;
      final anchor = RouteLabelLayout.anchorForPath(points, size);
      if (anchor == null) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: content.text,
          style: TextStyle(
            color: const Color(0xFF2C3828),
            fontSize: content.hasReference ? 10.5 : 10,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 138);
      final id = line.metadata.osmWayId ?? '${OsmLineProjector.seedFor(line)}';
      visuals[id] = _RouteLabelVisual(
        painter,
        colors: _colorsFor(
          content.membership,
          restricted: content.priority == -1,
          conditional: content.conditional,
        ),
      );
      candidates.add(
        RouteLabelCandidate(
          id: id,
          anchor: anchor,
          labelSize: Size(painter.width + 12, painter.height + 6),
          priority: content.priority,
        ),
      );
    }

    final placements = RouteLabelLayout.compose(
      candidates: candidates,
      viewport: size,
      reserved: [
        Rect.fromLTWH(0, 0, size.width, math.min(58, size.height)),
        if (size.width > 90 && size.height > 190)
          Rect.fromLTWH(size.width - 78, size.height - 190, 78, 190),
        if (size.height > 64)
          Rect.fromLTWH(0, size.height - 54, size.width, 54),
      ],
    );
    for (final placement in placements) {
      final visual = visuals[placement.id];
      if (visual == null) continue;
      canvas.drawRect(
        placement.rect.shift(const Offset(2, 2)),
        Paint()
          ..color = const Color(0x66202C21)
          ..isAntiAlias = false,
      );
      canvas.drawRect(
        placement.rect,
        Paint()
          ..color = visual.colors.border
          ..isAntiAlias = false,
      );
      canvas.drawRect(
        placement.rect.deflate(1),
        Paint()
          ..color = visual.colors.fill
          ..isAntiAlias = false,
      );
      visual.painter.paint(canvas, placement.rect.topLeft + const Offset(6, 3));
    }
  }

  _RouteLabelColors _colorsFor(
    HikingRouteMembership? membership, {
    required bool restricted,
    required bool conditional,
  }) {
    if (restricted) {
      return const _RouteLabelColors(Color(0xFF872B2B), Color(0xFFFFD5C8));
    }
    if (conditional) {
      return const _RouteLabelColors(Color(0xFF9B6A18), Color(0xFFFFE7A3));
    }
    return switch (membership?.network) {
      'iwn' => const _RouteLabelColors(Color(0xFF6E2830), Color(0xFFFFD7CF)),
      'nwn' => const _RouteLabelColors(Color(0xFF334D75), Color(0xFFDCEBFF)),
      'rwn' => const _RouteLabelColors(Color(0xFF3D6635), Color(0xFFE0F3D4)),
      'lwn' => const _RouteLabelColors(Color(0xFF70512E), Color(0xFFF7E4B5)),
      _ => const _RouteLabelColors(Color(0xFF6E5032), Color(0xFFF7E4B5)),
    };
  }

  @override
  bool shouldRepaint(_RouteLabelPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.features != features;
}

class _RouteLabelVisual {
  const _RouteLabelVisual(this.painter, {required this.colors});

  final TextPainter painter;
  final _RouteLabelColors colors;
}

class _RouteLabelColors {
  const _RouteLabelColors(this.border, this.fill);

  final Color border;
  final Color fill;
}
