import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../performance/map_rendering_budget.dart';
import 'water_edge_composer.dart';

/// Renders pixel-art water and its edge from arbitrary projected geometry.
///
/// A caller supplies OSM water polygon coordinates after projection into the
/// current logical map chunk. No mock coordinate or river-specific curve is
/// encoded here.
class PixelWaterPolygonLayer extends StatefulWidget {
  const PixelWaterPolygonLayer({
    super.key,
    required this.polygon,
    required this.material,
    required this.chunkSeed,
    this.edgeSpacing = 32,
    this.edgeScale = 1,
    this.maxEdgePlacements,
    this.flowDirection,
  });

  final List<Offset> polygon;
  final WaterEdgeMaterial material;
  final int chunkSeed;
  final double edgeSpacing;
  final double edgeScale;
  final int? maxEdgePlacements;

  /// Longitudinal flow axis in the projected coordinate space. A lake leaves
  /// this null; a river polygon supplies its downstream tangent.
  final Offset? flowDirection;

  @override
  State<PixelWaterPolygonLayer> createState() => _PixelWaterPolygonLayerState();
}

class _PixelWaterPolygonLayerState extends State<PixelWaterPolygonLayer>
    with WidgetsBindingObserver {
  static const _flowStep = Duration(milliseconds: 140);

  final ValueNotifier<double> _flowPhase = ValueNotifier(0);
  Timer? _flowTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.flowDirection != null) _startFlow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.flowDirection != null) _startFlow();
    } else {
      _flowTimer?.cancel();
      _flowTimer = null;
    }
  }

  void _startFlow() {
    if (_flowTimer?.isActive ?? false) return;
    _flowTimer = Timer.periodic(_flowStep, (_) {
      if (!MapRenderingBudget.mapVisible || MapRenderingBudget.mapInteracting) {
        return;
      }
      _flowPhase.value = (_flowPhase.value + 1 / 20) % 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flowTimer?.cancel();
    _flowPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edges =
        WaterEdgeComposer(
          spacing: widget.edgeSpacing,
          maxPlacements: widget.maxEdgePlacements,
        ).compose(
          polygon: widget.polygon,
          material: widget.material,
          chunkSeed: widget.chunkSeed,
        );
    final shoreAsset = switch (widget.material) {
      WaterEdgeMaterial.grass => 'assets/map/mock/terrain/shore_grass.png',
      WaterEdgeMaterial.rock => 'assets/map/mock/terrain/shore_rock_detail.png',
      WaterEdgeMaterial.sand => 'assets/map/mock/terrain/shore_sand_bank.png',
      WaterEdgeMaterial.mud => 'assets/map/mock/terrain/shore_mud_bank.png',
    };

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        AnimatedBuilder(
          animation: _flowPhase,
          builder: (context, _) => ClipPath(
            clipper: _PolygonClipper(widget.polygon),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The animated texture is intentionally translated along the
                // river axis. Keep a static water fill underneath it so a
                // missing asset can never expose the terrain layer.
                const ColoredBox(color: Color(0xFF28698A)),
                ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 256.0;
                      final viewportHeight = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 256.0;
                      // The child is deliberately larger than the clip.
                      // Without this overscan, translating a repeated
                      // DecorationImage exposes the solid fill at its
                      // leading edge once per flow tick.
                      const overscan = 32.0;
                      final textureWidth = viewportWidth + overscan * 2;
                      final textureHeight = viewportHeight + overscan * 2;
                      return OverflowBox(
                        alignment: Alignment.center,
                        minWidth: textureWidth,
                        maxWidth: textureWidth,
                        minHeight: textureHeight,
                        maxHeight: textureHeight,
                        child: Transform.translate(
                          offset: _flowOffset,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage(_waterAsset),
                                repeat: ImageRepeat.repeat,
                                filterQuality: FilterQuality.none,
                              ),
                            ),
                            child: SizedBox(
                              width: textureWidth,
                              height: textureHeight,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        CustomPaint(
          size: Size.infinite,
          painter: _WaterBoundaryPainter(
            polygon: widget.polygon,
            material: widget.material,
          ),
        ),
        for (final edge in edges)
          Positioned(
            left: edge.position.dx - 8 * widget.edgeScale,
            top: edge.position.dy - 8 * widget.edgeScale,
            width: 16 * widget.edgeScale,
            height: 16 * widget.edgeScale,
            child: Transform.rotate(
              // Shore modules are authored with land on the left and water
              // on the right.  Align that local +X water direction with the
              // actual inward normal; using the tangent flips the bank on
              // alternating segments of a curved/reversed OSM ring.
              angle: math.atan2(-edge.normal.dy, -edge.normal.dx),
              alignment: Alignment.center,
              child: Image.asset(
                shoreAsset,
                filterQuality: FilterQuality.none,
                isAntiAlias: false,
              ),
            ),
          ),
        // Sparse riparian accents sit farther onto land than the bank module.
        // They are derived from the same perimeter sample, so they cannot
        // drift independently while the camera moves.
        if (widget.material == WaterEdgeMaterial.grass)
          for (var index = 0; index < edges.length; index++)
            if ((index + edges[index].variant) % 5 == 0)
              Positioned(
                left:
                    edges[index].position.dx +
                    edges[index].normal.dx * 8 * widget.edgeScale -
                    7 * widget.edgeScale,
                top:
                    edges[index].position.dy +
                    edges[index].normal.dy * 8 * widget.edgeScale -
                    12 * widget.edgeScale,
                width: 14 * widget.edgeScale,
                height: 14 * widget.edgeScale,
                child: Image.asset(
                  'assets/map/mock/objects/shrub_riverside.png',
                  filterQuality: FilterQuality.none,
                  isAntiAlias: false,
                ),
              ),
      ],
    );
  }

  String get _waterAsset {
    final variant = widget.chunkSeed.abs() % 3 + 1;
    return 'assets/map/mock/terrain/water_still_$variant.png';
  }

  Offset get _flowOffset {
    final direction = widget.flowDirection;
    if (direction == null || direction.distance == 0) return Offset.zero;
    final normalized = direction / direction.distance;
    return normalized * (16 * _flowPhase.value);
  }
}

class _WaterBoundaryPainter extends CustomPainter {
  const _WaterBoundaryPainter({required this.polygon, required this.material});

  final List<Offset> polygon;
  final WaterEdgeMaterial material;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.length < 3 || size.isEmpty) return;
    final path = Path()..addPolygon(polygon, true);
    final inner = switch (material) {
      WaterEdgeMaterial.grass => const Color(0xFF708342),
      WaterEdgeMaterial.rock => const Color(0xFF777169),
      WaterEdgeMaterial.sand => const Color(0xFFD8AE68),
      WaterEdgeMaterial.mud => const Color(0xFF725238),
    };
    final outer = switch (material) {
      // A green containment outline between a muddy bank and the water reads
      // as exposed grass. Keep the water-facing edge in the same earth family.
      WaterEdgeMaterial.mud => const Color(0xFF503522),
      WaterEdgeMaterial.sand => const Color(0xFFB4874A),
      _ => const Color(0xFF294A46),
    };
    if (material == WaterEdgeMaterial.mud) {
      // The mud tile has transparent pixels at both sides so it cannot be
      // used as a watertight seal by itself. Paint a narrow continuous
      // earthen seam first; the pixel modules below add the irregular detail
      // without ever exposing the meadow between bank and water.
      canvas.drawPath(
        path,
        Paint()
          ..color = inner
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = false,
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = outer
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = false,
      );
    }
    if (material != WaterEdgeMaterial.mud) {
      canvas.drawPath(
        path,
        Paint()
          ..color = inner
          ..style = PaintingStyle.stroke
          // A continuous underlay closes the sub-pixel gaps between adjacent
          // 16px modules. The sprites remain the visible pixel-art detail.
          ..strokeWidth = switch (material) {
            WaterEdgeMaterial.sand => 3.5,
            _ => 1.2,
          }
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = false,
      );
    }
  }

  @override
  bool shouldRepaint(_WaterBoundaryPainter oldDelegate) =>
      oldDelegate.polygon != polygon || oldDelegate.material != material;
}

class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.polygon);

  final List<Offset> polygon;

  @override
  Path getClip(Size size) {
    if (polygon.isEmpty) return Path();
    return Path()..addPolygon(polygon, true);
  }

  @override
  bool shouldReclip(_PolygonClipper oldClipper) =>
      oldClipper.polygon != polygon;
}
