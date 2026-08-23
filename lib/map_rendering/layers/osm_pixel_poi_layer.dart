import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/semantics.dart';

import '../../domain/entities/map_feature_collection.dart';
import '../../domain/entities/poi.dart';
import '../../domain/enums/poi_type.dart';
import '../composition/poi_label_layout.dart';
import '../performance/map_rendering_budget.dart';

/// Batched POI/structure pass with geographic depth and Canvas semantics.
/// Individual markers no longer allocate widget, tooltip and image subtrees.
class OsmPixelPoiLayer extends StatefulWidget {
  const OsmPixelPoiLayer({super.key, required this.features, this.onPoiTap});

  final MapFeatureCollection features;
  final ValueChanged<Poi>? onPoiTap;

  @override
  State<OsmPixelPoiLayer> createState() => _OsmPixelPoiLayerState();
}

class _OsmPixelPoiLayerState extends State<OsmPixelPoiLayer> {
  static const _assets = [
    'assets/map/mock/structures/hut_alpine.png',
    'assets/map/mock/structures/hut_bivouac.png',
    'assets/map/mock/structures/guidepost_multi.png',
    'assets/map/mock/structures/trail_marker_low.png',
    'assets/map/mock/structures/boulder.png',
  ];

  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  Offset? _pointerDown;
  bool _pointerMoved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final asset in _assets) {
      if (_images.containsKey(asset) || !_loading.add(asset)) continue;
      _loadImage(asset);
    }
  }

  Future<void> _loadImage(String asset) async {
    final completer = Completer<ui.Image>();
    final stream = AssetImage(
      asset,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        stream.removeListener(listener);
        completer.complete(image.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    try {
      final image = await completer.future;
      if (mounted) setState(() => _images[asset] = image);
    } catch (_) {
      // Procedural glyphs preserve every POI if artwork cannot be loaded.
    } finally {
      _loading.remove(asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final pois = widget.features.pois
        .where((poi) => poi.type != PoiType.tree)
        .toList(growable: false);
    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointerDown = event.localPosition;
          _pointerMoved = false;
        },
        onPointerMove: (event) {
          final down = _pointerDown;
          if (down != null && (event.localPosition - down).distance > 8) {
            _pointerMoved = true;
          }
        },
        onPointerCancel: (_) {
          _pointerDown = null;
          _pointerMoved = false;
        },
        onPointerUp: (event) {
          if (!_pointerMoved) {
            final poi = _hitTestPoi(
              camera,
              pois,
              event.localPosition,
              context.size ?? Size.zero,
            );
            if (poi != null) widget.onPoiTap?.call(poi);
          }
          _pointerDown = null;
          _pointerMoved = false;
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _PoiPainter(
            camera: camera,
            pois: pois,
            images: Map.unmodifiable(_images),
            onPoiTap: widget.onPoiTap,
          ),
        ),
      ),
    );
  }

  Poi? _hitTestPoi(
    MapCamera camera,
    List<Poi> pois,
    Offset tap,
    Size viewport,
  ) {
    for (final label in _composePoiLabels(camera, pois, viewport)) {
      if (label.rect.inflate(3).contains(tap)) return label.poi;
    }
    Poi? closest;
    var closestDistance = double.infinity;
    for (final poi in pois) {
      final markerSize = MapRenderingBudget.poiMarkerSize(
        poi.type,
        camera.zoom,
      );
      final center = camera
          .latLngToScreenOffset(poi.position)
          .translate(0, -markerSize / 2);
      final distance = (tap - center).distance;
      final hitRadius = math.max(22.0, markerSize * .72);
      if (distance <= hitRadius && distance < closestDistance) {
        closest = poi;
        closestDistance = distance;
      }
    }
    return closest;
  }
}

class _PoiPainter extends CustomPainter {
  const _PoiPainter({
    required this.camera,
    required this.pois,
    required this.images,
    required this.onPoiTap,
  });

  final MapCamera camera;
  final List<Poi> pois;
  final Map<String, ui.Image> images;
  final ValueChanged<Poi>? onPoiTap;

  List<Poi> get _visiblePois {
    final visible = pois
        .where((poi) => camera.visibleBounds.contains(poi.position))
        .toList(growable: false);
    // North/background first, south/foreground last.
    visible.sort((a, b) {
      final depth = b.position.latitude.compareTo(a.position.latitude);
      if (depth != 0) return depth;
      return a.id.compareTo(b.id);
    });
    return visible;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final imagePaint = Paint()..filterQuality = FilterQuality.none;
    for (final poi in _visiblePois) {
      final foot = camera.latLngToScreenOffset(poi.position);
      final markerSize = MapRenderingBudget.poiMarkerSize(
        poi.type,
        camera.zoom,
      );
      if (foot.dx < -markerSize ||
          foot.dy < -markerSize ||
          foot.dx > size.width + markerSize ||
          foot.dy > size.height + markerSize) {
        continue;
      }
      final asset = _assetFor(poi);
      final image = asset == null ? null : images[asset];
      if (image == null) {
        _paintGlyph(canvas, foot, markerSize, poi.type);
        continue;
      }
      final imageScale = math.min(
        markerSize / image.width,
        markerSize / image.height,
      );
      final width = image.width * imageScale;
      final height = image.height * imageScale;
      canvas.drawOval(
        Rect.fromCenter(
          center: foot.translate(0, -1),
          width: width * .72,
          height: math.max(2, height * .13),
        ),
        Paint()..color = const Color(0x55202C21),
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(foot.dx - width / 2, foot.dy - height, width, height),
        imagePaint,
      );
    }
    for (final label in _composePoiLabels(camera, _visiblePois, size)) {
      _paintLabel(canvas, label);
    }
  }

  void _paintLabel(Canvas canvas, _PoiLabelVisual label) {
    final rect = label.rect;
    final shadowPaint = Paint()
      ..color = const Color(0x77202C21)
      ..isAntiAlias = false;
    final borderPaint = Paint()
      ..color = const Color(0xFF5B432E)
      ..isAntiAlias = false;
    final fillPaint = Paint()
      ..color = const Color(0xF7FFF4D1)
      ..isAntiAlias = false;
    canvas.drawRect(rect.shift(const Offset(2, 2)), shadowPaint);
    canvas.drawRect(rect, borderPaint);
    canvas.drawRect(rect.deflate(1), fillPaint);
    label.textPainter.paint(canvas, rect.topLeft + const Offset(6, 3));
  }

  String? _assetFor(Poi poi) => switch (poi.type) {
    PoiType.shelter =>
      _stableSeed(poi.id).isEven
          ? 'assets/map/mock/structures/hut_alpine.png'
          : 'assets/map/mock/structures/hut_bivouac.png',
    PoiType.viewpoint ||
    PoiType.guidepost => 'assets/map/mock/structures/guidepost_multi.png',
    PoiType.campsite => 'assets/map/mock/structures/trail_marker_low.png',
    PoiType.summit => 'assets/map/mock/structures/boulder.png',
    PoiType.parking || PoiType.waterSource || PoiType.tree => null,
  };

  int _stableSeed(String id) {
    var seed = 17;
    for (final unit in id.codeUnits) {
      seed = seed * 31 + unit;
    }
    return seed.abs();
  }

  void _paintGlyph(
    Canvas canvas,
    Offset foot,
    double markerSize,
    PoiType type,
  ) {
    final dimension = markerSize * .76;
    final center = foot.translate(0, -dimension / 2);
    canvas.drawCircle(
      center.translate(1.5, 2),
      dimension / 2,
      Paint()..color = const Color(0x55202C21),
    );
    canvas.drawCircle(
      center,
      dimension / 2,
      Paint()..color = const Color(0xFFFFF7DA),
    );
    canvas.drawCircle(
      center,
      dimension / 2,
      Paint()
        ..color = const Color(0xFF684C32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, markerSize * .055)
        ..isAntiAlias = false,
    );
    final pixel = math.max(1.0, markerSize / 13);
    final glyph = Paint()..isAntiAlias = false;
    switch (type) {
      case PoiType.parking:
        glyph.color = const Color(0xFF315E7A);
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - 3 * pixel,
            center.dy - 4 * pixel,
            2 * pixel,
            8 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 4 * pixel,
            4 * pixel,
            2 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 2 * pixel,
            3 * pixel,
            2 * pixel,
          ),
          glyph,
        );
      case PoiType.waterSource:
        glyph.color = const Color(0xFF2E83A6);
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - pixel,
            center.dy - 4 * pixel,
            2 * pixel,
            6 * pixel,
          ),
          glyph,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - 3 * pixel,
            center.dy + pixel,
            6 * pixel,
            2 * pixel,
          ),
          glyph,
        );
      default:
        glyph.color = const Color(0xFF376342);
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 2 * pixel, height: 8 * pixel),
          glyph,
        );
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 8 * pixel, height: 2 * pixel),
          glyph,
        );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final labels = {
      for (final label in _composePoiLabels(camera, _visiblePois, size))
        label.poi.id: label.rect,
    };
    return [
      for (final poi in _visiblePois)
        CustomPainterSemantics(
          rect:
              labels[poi.id]?.expandToInclude(
                Rect.fromCenter(
                  center: camera
                      .latLngToScreenOffset(poi.position)
                      .translate(
                        0,
                        -MapRenderingBudget.poiMarkerSize(
                              poi.type,
                              camera.zoom,
                            ) /
                            2,
                      ),
                  width: MapRenderingBudget.poiMarkerSize(
                    poi.type,
                    camera.zoom,
                  ),
                  height: MapRenderingBudget.poiMarkerSize(
                    poi.type,
                    camera.zoom,
                  ),
                ),
              ) ??
              Rect.fromCenter(
                center: camera
                    .latLngToScreenOffset(poi.position)
                    .translate(
                      0,
                      -MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom) /
                          2,
                    ),
                width: MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom),
                height: MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom),
              ),
          properties: SemanticsProperties(
            label: poi.name,
            button: onPoiTap != null,
            onTap: onPoiTap == null ? null : () => onPoiTap!(poi),
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRepaint(_PoiPainter oldDelegate) =>
      oldDelegate.camera.center != camera.center ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.rotation != camera.rotation ||
      oldDelegate.pois != pois ||
      oldDelegate.images != images ||
      oldDelegate.onPoiTap != onPoiTap;

  @override
  bool shouldRebuildSemantics(_PoiPainter oldDelegate) =>
      shouldRepaint(oldDelegate);
}

const _poiLabelStyle = TextStyle(
  color: Color(0xFF273426),
  fontSize: 11,
  fontWeight: FontWeight.w800,
  height: 1.05,
);

class _PoiLabelVisual {
  const _PoiLabelVisual({
    required this.poi,
    required this.rect,
    required this.textPainter,
  });

  final Poi poi;
  final Rect rect;
  final TextPainter textPainter;
}

List<_PoiLabelVisual> _composePoiLabels(
  MapCamera camera,
  List<Poi> pois,
  Size viewport,
) {
  if (viewport.isEmpty) return const [];
  final visible = <Poi>[];
  final markerRects = <String, Rect>{};
  for (final poi in pois) {
    if (poi.type == PoiType.tree ||
        !camera.visibleBounds.contains(poi.position)) {
      continue;
    }
    final markerSize = MapRenderingBudget.poiMarkerSize(poi.type, camera.zoom);
    final foot = camera.latLngToScreenOffset(poi.position);
    final rect = Rect.fromLTWH(
      foot.dx - markerSize / 2,
      foot.dy - markerSize,
      markerSize,
      markerSize,
    );
    if (!rect.inflate(markerSize).overlaps(Offset.zero & viewport)) continue;
    visible.add(poi);
    markerRects[poi.id] = rect;
  }

  final painters = <String, TextPainter>{};
  final candidates = <PoiLabelCandidate>[];
  for (final poi in visible) {
    if (camera.zoom < MapRenderingBudget.poiLabelMinZoom(poi.type) ||
        poi.name.trim().isEmpty) {
      continue;
    }
    final painter = TextPainter(
      text: TextSpan(text: poi.name.trim(), style: _poiLabelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 124);
    painters[poi.id] = painter;
    candidates.add(
      PoiLabelCandidate(
        id: poi.id,
        markerRect: markerRects[poi.id]!,
        labelSize: Size(painter.width + 12, painter.height + 6),
        priority: MapRenderingBudget.poiPriority(poi.type),
      ),
    );
  }

  final placements = PoiLabelLayout.compose(
    candidates: candidates,
    viewport: viewport,
    reserved: [
      Rect.fromLTWH(0, 0, viewport.width, math.min(58, viewport.height)),
      if (viewport.width > 90 && viewport.height > 190)
        Rect.fromLTWH(viewport.width - 78, viewport.height - 190, 78, 190),
      if (viewport.height > 64)
        Rect.fromLTWH(0, viewport.height - 54, viewport.width, 54),
    ],
  );
  final poiById = {for (final poi in visible) poi.id: poi};
  return [
    for (final placement in placements)
      if (poiById[placement.id] case final poi?)
        _PoiLabelVisual(
          poi: poi,
          rect: placement.rect,
          textPainter: painters[placement.id]!,
        ),
  ];
}
