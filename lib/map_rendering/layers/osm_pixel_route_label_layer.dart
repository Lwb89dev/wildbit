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
  const OsmPixelRouteLabelLayer({super.key, required this.features});

  final MapFeatureCollection features;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RouteLabelPainter(
            camera: MapCamera.of(context),
            features: features,
          ),
        ),
      ),
    );
  }
}

class _RouteLabelPainter extends CustomPainter {
  const _RouteLabelPainter({required this.camera, required this.features});

  final MapCamera camera;
  final MapFeatureCollection features;

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

      final points = OsmLineProjector.projectSimplified(
        line,
        camera.latLngToScreenOffset,
        minimumDistancePixels: math.max(
          MapRenderingBudget.minLinePointDistancePixels,
          18 - camera.zoom,
        ),
      );
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
        colors: _colorsFor(content.membership, content.priority < 0),
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
    HikingRouteMembership? membership,
    bool restricted,
  ) {
    if (restricted) {
      return const _RouteLabelColors(Color(0xFF872B2B), Color(0xFFFFD5C8));
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
