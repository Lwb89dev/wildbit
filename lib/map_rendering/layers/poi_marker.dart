import 'package:flutter/material.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../domain/enums/poi_type.dart';

String? _assetFor(PoiType type, int variant) => switch (type) {
  PoiType.shelter => variant.isEven
      ? 'assets/map/mock/structures/hut_alpine.png'
      : 'assets/map/mock/structures/hut_bivouac.png',
  PoiType.viewpoint || PoiType.guidepost =>
    'assets/map/mock/structures/guidepost_multi.png',
  PoiType.campsite => 'assets/map/mock/structures/trail_marker_low.png',
  PoiType.summit => 'assets/map/mock/structures/boulder.png',
  PoiType.parking || PoiType.waterSource || PoiType.tree => null,
};

/// A compact, elevated marker that belongs to the illustrated map rather than
/// looking like a system icon placed on top of it.
class PoiMarker extends StatelessWidget {
  const PoiMarker({
    super.key,
    required this.type,
    required this.label,
    this.variantSeed = 0,
  });

  final PoiType type;
  final String label;
  final int variantSeed;

  @override
  Widget build(BuildContext context) {
    final asset = _assetFor(type, variantSeed);
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: asset == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFCF0), Color(0xFFE6DDBF)],
                ),
                border: Border.all(
                  color: WildBitColors.brown.withValues(alpha: .85),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF263325).withValues(alpha: .35),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _PixelPoiGlyphPainter(type),
              ),
            )
            : Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 1,
                    height: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2B20).withValues(alpha: .32),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Image.asset(
                      asset,
                      alignment: Alignment.bottomCenter,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      isAntiAlias: false,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PixelPoiGlyphPainter extends CustomPainter {
  const _PixelPoiGlyphPainter(this.type);

  final PoiType type;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = WildBitColors.forestGreen;
    final x = size.width / 2;
    final y = size.height / 2;
    switch (type) {
      case PoiType.parking:
        paint.color = const Color(0xFF315E7A);
        canvas.drawRect(Rect.fromLTWH(x - 5, y - 7, 3, 14), paint);
        canvas.drawRect(Rect.fromLTWH(x - 2, y - 7, 6, 3), paint);
        canvas.drawRect(Rect.fromLTWH(x - 2, y - 4, 5, 3), paint);
      case PoiType.waterSource:
        paint.color = const Color(0xFF3C89AA);
        canvas.drawRect(Rect.fromLTWH(x - 2, y - 7, 4, 11), paint);
        canvas.drawRect(Rect.fromLTWH(x - 5, y + 2, 10, 3), paint);
        canvas.drawRect(Rect.fromLTWH(x - 6, y + 5, 12, 2), paint);
      default:
        paint.color = WildBitColors.forestGreen;
        canvas.drawRect(Rect.fromLTWH(x - 2, y - 6, 4, 12), paint);
        canvas.drawRect(Rect.fromLTWH(x - 6, y - 2, 12, 4), paint);
    }
  }

  @override
  bool shouldRepaint(_PixelPoiGlyphPainter oldDelegate) =>
      oldDelegate.type != type;
}
