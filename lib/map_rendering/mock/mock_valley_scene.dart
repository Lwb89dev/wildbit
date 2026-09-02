import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mock_environment_sprite_layer.dart';
import 'mock_low_rock_sprite_layer.dart';
import 'mock_lake_texture_layer.dart';
import 'mock_riverbank_texture_layer.dart';
import 'mock_structure_sprite_layer.dart';
import 'mock_terrain_texture_layer.dart';
import 'mock_trail_texture_layer.dart';
import 'mock_bit_sprite_layer.dart';
import 'mock_recorded_track_layer.dart';

/// A fixed 256×256 logical-pixel scene used to validate WildBit's composition
/// rules before real OSM chunks and final sprites are introduced.
///
/// This is deliberately a scene renderer, not a map widget: its only job is
/// to make layering, anchors and occlusion visible and testable in isolation.
class MockValleyScene extends StatelessWidget {
  const MockValleyScene({
    super.key,
    this.showDebug = false,
    this.showLake = false,
  });

  final bool showDebug;
  final bool showLake;

  @override
  Widget build(BuildContext context) {
    // Fractional FittedBox scales (for example 2.5× inside a 640 px preview)
    // put sprite edges between physical pixels and make a clean silhouette
    // look clipped. Keep the native 256 px grid and use only integer scales;
    // the unused space is intentionally centred around the scene.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MockValleyPainter.logicalSize;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MockValleyPainter.logicalSize;
        final scale = math.max(
          1.0,
          math
              .min(
                width / MockValleyPainter.logicalSize,
                height / MockValleyPainter.logicalSize,
              )
              .floorToDouble(),
        );
        final sceneSize = MockValleyPainter.logicalSize * scale;
        return Center(
          child: SizedBox(
            width: sceneSize,
            height: sceneSize,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: MockValleyPainter.logicalSize,
                height: MockValleyPainter.logicalSize,
                child: Stack(
                  children: [
                    const MockTerrainTextureLayer(),
                    if (showLake) const MockLakeTextureLayer(),
                    const MockRiverbankTextureLayer(),
                    const MockLowRockSpriteLayer(),
                    CustomPaint(
                      size: const Size(
                        MockValleyPainter.logicalSize,
                        MockValleyPainter.logicalSize,
                      ),
                      painter: const MockValleyPainter(
                        paintTerrainBase: false,
                        paintMapDetails: true,
                        paintRiverBanks: false,
                        paintStructuralRocks: false,
                        paintTrailAndBridge: false,
                        paintSilhouetteVegetation: false,
                        paintPoiAndDynamic: false,
                      ),
                    ),
                    const MockTrailTextureLayer(),
                    const MockRecordedTrackLayer(),
                    const MockEnvironmentSpriteLayer(),
                    const MockStructureSpriteLayer(),
                    const MockBitSpriteLayer(),
                    CustomPaint(
                      size: const Size(
                        MockValleyPainter.logicalSize,
                        MockValleyPainter.logicalSize,
                      ),
                      painter: MockValleyPainter(
                        showDebug: showDebug,
                        paintTerrainBase: false,
                        paintMapDetails: false,
                        paintTrailAndBridge: false,
                        paintSilhouetteVegetation: false,
                        paintPoiAndDynamic: false,
                        paintStaticPoi: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MockValleyPainter extends CustomPainter {
  const MockValleyPainter({
    this.showDebug = false,
    this.paintTerrainBase = true,
    this.paintMapDetails = true,
    this.paintRiverBanks = true,
    this.paintStructuralRocks = true,
    this.paintTrailAndBridge = true,
    this.paintSilhouetteVegetation = true,
    this.paintPoiAndDynamic = true,
    this.paintStaticPoi = true,
  });

  static const logicalSize = 256.0;

  final bool showDebug;

  /// Flat-colour fallback for the terrain texture layer. This remains useful
  /// in isolated painter tests, but the live mock now uses native pixel tiles.
  final bool paintTerrainBase;
  final bool paintMapDetails;
  final bool paintRiverBanks;
  final bool paintStructuralRocks;
  final bool paintTrailAndBridge;
  final bool paintSilhouetteVegetation;
  final bool paintPoiAndDynamic;

  /// Real huts and guideposts live in [MockStructureSpriteLayer].
  final bool paintStaticPoi;

  static const _grass = Color(0xFF6F963D);
  static const _grassLight = Color(0xFF9CBC4A);
  static const _forest = Color(0xFF1C4736);
  static const _forestLight = Color(0xFF2F6540);
  static const _water = Color(0xFF28698A);
  static const _waterLight = Color(0xFF4D97B6);
  static const _shore = Color(0xFF426A31);
  static const _trail = Color(0xFFD2A866);
  static const _trailEdge = Color(0xFF765031);
  static const _rock = Color(0xFF59605C);
  static const _rockLight = Color(0xFFB5AD96);
  static const _wood = Color(0xFF765031);
  static const _shadow = Color(0x73102A28);
  static const _debug = Color(0x59FF00FF);

  Paint _paint(Color color) => Paint()
    ..color = color
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / logicalSize;
    canvas.save();
    canvas.scale(scale, scale);

    if (paintTerrainBase) {
      // 1. Water and base terrain.
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, logicalSize, logicalSize),
        _paint(_grass),
      );
      _paintRiver(canvas);
      _paintMeadowTexture(canvas);
    }

    if (paintMapDetails) {
      // 2. Shore and structural rocks.
      if (paintRiverBanks) _paintRiverBanks(canvas);
      if (paintStructuralRocks) _paintStructuralRocks(canvas);

      // 3. Background vegetation.
      _paintFlowersAndReeds(canvas);
    }

    if (paintTrailAndBridge) {
      // 4. Paths and roads.
      _paintTrail(canvas);
      _paintBridge(canvas);
    }

    if (paintSilhouetteVegetation) {
      _paintForestMasses(canvas);
      _paintTrees(canvas);
      _paintShrubs(canvas);
    }

    if (paintPoiAndDynamic) {
      // 6. POIs and structures.
      if (paintStaticPoi) {
        _paintGuidepost(canvas, const Offset(104, 147));
        _paintHut(canvas, const Offset(57, 62));
      }

      // 7. Dynamic-world placeholder: this is where Bit and a recorded track
      // will be drawn by the map integration, above the bridge and path.
      _paintBitPlaceholder(canvas, const Offset(119, 167));
    }

    if (showDebug) _paintDebug(canvas);
    canvas.restore();
  }

  void _paintRiver(Canvas canvas) {
    final river = Path()
      ..moveTo(205, 0)
      ..cubicTo(177, 36, 218, 67, 192, 101)
      ..cubicTo(165, 136, 219, 169, 192, 205)
      ..cubicTo(177, 224, 191, 244, 178, 256)
      ..lineTo(232, 256)
      ..lineTo(232, 0)
      ..close();
    canvas.drawPath(river, _paint(_water));

    for (var y = 12.0; y < 252; y += 19) {
      final x = 215.0 + ((y ~/ 19) % 2) * 8;
      canvas.drawRect(Rect.fromLTWH(x, y, 13, 2), _paint(_waterLight));
      canvas.drawRect(Rect.fromLTWH(x + 4, y + 3, 7, 1), _paint(_waterLight));
    }
  }

  void _paintMeadowTexture(Canvas canvas) {
    for (var y = 8.0; y < 256; y += 16) {
      for (var x = 8.0; x < 180; x += 19) {
        if ((x ~/ 19 + y ~/ 16) % 3 != 0) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, 3, 2), _paint(_grassLight));
      }
    }
  }

  void _paintRiverBanks(Canvas canvas) {
    final leftBank = Path()
      ..moveTo(201, 0)
      ..cubicTo(173, 36, 214, 67, 188, 101)
      ..cubicTo(161, 136, 215, 169, 188, 205)
      ..cubicTo(173, 224, 187, 244, 174, 256)
      ..lineTo(181, 256)
      ..cubicTo(197, 243, 185, 223, 200, 208)
      ..cubicTo(227, 171, 173, 137, 200, 103)
      ..cubicTo(226, 67, 186, 37, 213, 0)
      ..close();
    canvas.drawPath(leftBank, _paint(_shore));

    for (final point in [
      const Offset(190, 25),
      const Offset(187, 89),
      const Offset(183, 129),
      const Offset(190, 195),
      const Offset(180, 235),
    ]) {
      _paintRock(canvas, point, wet: true);
    }
  }

  void _paintStructuralRocks(Canvas canvas) {
    for (final point in [
      const Offset(39, 87),
      const Offset(151, 45),
      const Offset(154, 210),
    ]) {
      _paintRock(canvas, point);
    }
  }

  void _paintForestMasses(Canvas canvas) {
    for (final point in [
      const Offset(15, 24),
      const Offset(44, 19),
      const Offset(76, 34),
      const Offset(21, 110),
      const Offset(47, 201),
      const Offset(91, 224),
      const Offset(137, 21),
      const Offset(154, 82),
      const Offset(225, 32),
    ]) {
      _paintTree(canvas, point, conifer: point.dy > 195 || point.dx > 130);
    }
  }

  void _paintFlowersAndReeds(Canvas canvas) {
    for (final point in [
      const Offset(73, 102),
      const Offset(128, 87),
      const Offset(61, 160),
      const Offset(139, 187),
    ]) {
      canvas.drawRect(
        Rect.fromLTWH(point.dx, point.dy, 3, 3),
        _paint(const Color(0xFFB66AB1)),
      );
      canvas.drawRect(
        Rect.fromLTWH(point.dx + 5, point.dy + 3, 2, 2),
        _paint(const Color(0xFFF2F0D4)),
      );
    }
    for (final point in [const Offset(181, 71), const Offset(183, 161)]) {
      canvas.drawRect(
        Rect.fromLTWH(point.dx, point.dy, 2, 8),
        _paint(_forestLight),
      );
      canvas.drawRect(
        Rect.fromLTWH(point.dx + 4, point.dy - 2, 2, 10),
        _paint(_forestLight),
      );
    }
  }

  void _paintTrail(Canvas canvas) {
    final trail = Path()
      ..moveTo(92, 256)
      ..cubicTo(95, 219, 126, 202, 113, 167)
      ..cubicTo(100, 135, 151, 115, 131, 81)
      ..cubicTo(113, 49, 124, 22, 108, 0);
    canvas.drawPath(
      trail,
      _paint(_trailEdge)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.square,
    );
    canvas.drawPath(
      trail,
      _paint(_trail)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.square,
    );
  }

  void _paintBridge(Canvas canvas) {
    // A horizontal pedestrian bridge crosses the stream at y=120.
    canvas.drawRect(const Rect.fromLTWH(176, 115, 64, 12), _paint(_shadow));
    canvas.drawRect(const Rect.fromLTWH(174, 111, 64, 12), _paint(_wood));
    for (var x = 176; x < 238; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 112, 2, 10), _paint(_trail));
    }
  }

  void _paintTrees(Canvas canvas) {
    for (final point in [
      const Offset(21, 58),
      const Offset(55, 127),
      const Offset(77, 187),
      const Offset(145, 151),
      const Offset(159, 225),
      const Offset(229, 89),
    ]) {
      _paintTree(canvas, point, conifer: point.dx > 140);
    }
  }

  void _paintShrubs(Canvas canvas) {
    for (final point in [
      const Offset(74, 130),
      const Offset(137, 112),
      const Offset(150, 178),
      const Offset(57, 235),
    ]) {
      canvas.drawOval(
        Rect.fromLTWH(point.dx, point.dy, 17, 10),
        _paint(_forestLight),
      );
      canvas.drawRect(
        Rect.fromLTWH(point.dx + 3, point.dy + 8, 11, 3),
        _paint(_forest),
      );
    }
  }

  void _paintTree(Canvas canvas, Offset foot, {required bool conifer}) {
    canvas.drawOval(
      Rect.fromLTWH(foot.dx - 10, foot.dy - 2, 20, 7),
      _paint(_shadow),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 2, foot.dy - 18, 4, 18),
      _paint(_wood),
    );
    if (conifer) {
      canvas.drawPath(
        Path()
          ..moveTo(foot.dx, foot.dy - 39)
          ..lineTo(foot.dx - 14, foot.dy - 9)
          ..lineTo(foot.dx + 14, foot.dy - 9)
          ..close(),
        _paint(_forest),
      );
      canvas.drawPath(
        Path()
          ..moveTo(foot.dx, foot.dy - 30)
          ..lineTo(foot.dx - 17, foot.dy - 3)
          ..lineTo(foot.dx + 17, foot.dy - 3)
          ..close(),
        _paint(_forestLight),
      );
      return;
    }
    canvas.drawCircle(foot - const Offset(0, 24), 13, _paint(_forest));
    canvas.drawCircle(foot - const Offset(6, 28), 8, _paint(_forestLight));
  }

  void _paintRock(Canvas canvas, Offset foot, {bool wet = false}) {
    canvas.drawOval(
      Rect.fromLTWH(foot.dx - 8, foot.dy - 2, 16, 5),
      _paint(_shadow),
    );
    final path = Path()
      ..moveTo(foot.dx - 8, foot.dy - 2)
      ..lineTo(foot.dx - 5, foot.dy - 13)
      ..lineTo(foot.dx + 4, foot.dy - 15)
      ..lineTo(foot.dx + 9, foot.dy - 4)
      ..lineTo(foot.dx + 6, foot.dy)
      ..lineTo(foot.dx - 7, foot.dy)
      ..close();
    canvas.drawPath(path, _paint(wet ? _waterLight : _rock));
    canvas.drawPath(
      Path()
        ..moveTo(foot.dx - 5, foot.dy - 13)
        ..lineTo(foot.dx + 4, foot.dy - 15)
        ..lineTo(foot.dx, foot.dy - 6)
        ..close(),
      _paint(_rockLight),
    );
  }

  void _paintGuidepost(Canvas canvas, Offset foot) {
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 1, foot.dy - 18, 3, 18),
      _paint(_wood),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 8, foot.dy - 17, 16, 4),
      _paint(_trail),
    );
  }

  void _paintHut(Canvas canvas, Offset foot) {
    canvas.drawOval(
      Rect.fromLTWH(foot.dx - 19, foot.dy - 2, 38, 7),
      _paint(_shadow),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 18, foot.dy - 24, 36, 23),
      _paint(_wood),
    );
    canvas.drawPath(
      Path()
        ..moveTo(foot.dx - 22, foot.dy - 24)
        ..lineTo(foot.dx, foot.dy - 40)
        ..lineTo(foot.dx + 22, foot.dy - 24)
        ..close(),
      _paint(_trailEdge),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 3, foot.dy - 11, 6, 10),
      _paint(_trailEdge),
    );
  }

  void _paintBitPlaceholder(Canvas canvas, Offset foot) {
    canvas.drawOval(
      Rect.fromLTWH(foot.dx - 7, foot.dy - 1, 14, 4),
      _paint(_shadow),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 4, foot.dy - 13, 8, 12),
      _paint(const Color(0xFFE88432)),
    );
    canvas.drawCircle(
      foot - const Offset(0, 17),
      6,
      _paint(const Color(0xFFE88432)),
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx + 7, foot.dy - 15, 2, 16),
      _paint(_wood),
    );
  }

  void _paintDebug(Canvas canvas) {
    final paint = _paint(_debug)..style = PaintingStyle.stroke;
    canvas.drawRect(const Rect.fromLTWH(111, 159, 16, 8), paint);
    canvas.drawRect(const Rect.fromLTWH(35, 50, 44, 16), paint);
    canvas.drawRect(const Rect.fromLTWH(100, 142, 8, 5), paint);
    canvas.drawLine(const Offset(0, 128), const Offset(256, 128), paint);
    canvas.drawLine(const Offset(128, 0), const Offset(128, 256), paint);
  }

  @override
  bool shouldRepaint(covariant MockValleyPainter oldDelegate) =>
      oldDelegate.showDebug != showDebug ||
      oldDelegate.paintTerrainBase != paintTerrainBase ||
      oldDelegate.paintMapDetails != paintMapDetails ||
      oldDelegate.paintRiverBanks != paintRiverBanks ||
      oldDelegate.paintStructuralRocks != paintStructuralRocks ||
      oldDelegate.paintTrailAndBridge != paintTrailAndBridge ||
      oldDelegate.paintSilhouetteVegetation != paintSilhouetteVegetation ||
      oldDelegate.paintPoiAndDynamic != paintPoiAndDynamic ||
      oldDelegate.paintStaticPoi != paintStaticPoi;
}
