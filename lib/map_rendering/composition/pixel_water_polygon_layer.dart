import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  });

  final List<Offset> polygon;
  final WaterEdgeMaterial material;
  final int chunkSeed;
  final double edgeSpacing;
  final double edgeScale;
  final int? maxEdgePlacements;

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
    _startFlow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startFlow();
    } else {
      _flowTimer?.cancel();
      _flowTimer = null;
    }
  }

  void _startFlow() {
    if (_flowTimer?.isActive ?? false) return;
    _flowTimer = Timer.periodic(_flowStep, (_) {
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
    final edges = WaterEdgeComposer(
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
      WaterEdgeMaterial.sand => 'assets/map/mock/terrain/shore_sand.png',
    };

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        AnimatedBuilder(
          animation: _flowPhase,
          builder: (context, child) => ClipPath(
            clipper: _PolygonClipper(widget.polygon),
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(-16 * _flowPhase.value, 0),
                child: child,
              ),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(_waterAsset),
                repeat: ImageRepeat.repeat,
                filterQuality: FilterQuality.none,
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
        for (final edge in edges)
          Positioned(
            left: edge.position.dx - 8 * widget.edgeScale,
            top: edge.position.dy - 8 * widget.edgeScale,
            width: 16 * widget.edgeScale,
            height: 16 * widget.edgeScale,
            child: Transform.rotate(
              angle: math.atan2(edge.tangent.dy, edge.tangent.dx),
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
                left: edges[index].position.dx +
                    edges[index].normal.dx * 8 * widget.edgeScale -
                    7 * widget.edgeScale,
                top: edges[index].position.dy +
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
