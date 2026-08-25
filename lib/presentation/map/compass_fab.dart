import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/wildbit_theme.dart';

/// Small round compass control, mirroring the map's current rotation.
/// Tap toggles between north-up and heading-up (magnetometer-driven) modes —
/// see [CompassHeadingService] for where the heading itself comes from.
class CompassFab extends StatelessWidget {
  const CompassFab({
    super.key,
    required this.rotationDegrees,
    required this.headingModeActive,
    required this.onTap,
  });

  /// Current map rotation in degrees (0 = north-up).
  final double rotationDegrees;

  /// Whether the map is currently following the compass/heading instead of
  /// staying north-up.
  final bool headingModeActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.surface2,
          shape: BoxShape.circle,
          border: headingModeActive ? Border.all(color: colors.accent, width: 2) : null,
          boxShadow: [
            const BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
            if (headingModeActive)
              BoxShadow(color: colors.accent.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        child: Transform.rotate(
          angle: -rotationDegrees * math.pi / 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.navigation_rounded,
                color: headingModeActive ? colors.accent : colors.textSecondary,
                size: 26,
              ),
              const Positioned(
                top: 5,
                child: Text(
                  'N',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
