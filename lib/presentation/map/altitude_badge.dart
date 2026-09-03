import 'package:flutter/material.dart';

import '../../app/theme/wildbit_theme.dart';

/// Compact live-altitude readout, matching CompassFab's theme-aware style so
/// the right-side button column reads as one instrument cluster.
///
/// Reads straight from the same GPS fix already driving the map's position
/// marker — no separate barometer dependency, so it is exactly as accurate
/// (and exactly as available) as the position dot itself.
class AltitudeBadge extends StatelessWidget {
  const AltitudeBadge({super.key, required this.altitudeMeters});

  final double? altitudeMeters;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    final altitude = altitudeMeters;
    final label = (altitude == null || !altitude.isFinite)
        ? '—'
        : '${altitude.round()} m';
    return Container(
      height: 44,
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terrain_rounded, size: 18, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
