import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/line_feature.dart';
import '../../domain/entities/trail_classification.dart';
import '../../domain/enums/map_feature_kind.dart';
import '../performance/map_rendering_budget.dart';

enum RouteTextureFamily { trail, track, paved }

class RouteVisualStyle {
  const RouteVisualStyle({
    required this.family,
    required this.width,
    required this.outlineWidth,
    required this.fallbackColor,
    required this.outlineColor,
    required this.difficulty,
    required this.access,
    required this.visibility,
  });

  final RouteTextureFamily family;
  final double width;
  final double outlineWidth;
  final Color fallbackColor;
  final Color outlineColor;
  final TrailDifficulty difficulty;
  final TrailAccessStatus access;
  final TrailVisibilityStatus visibility;

  static RouteVisualStyle forLine(LineFeature line, double zoom) {
    final family = _family(line);
    final scale = MapRenderingBudget.decorativeScale(zoom, min: .12, max: 1.0);
    final baseWidth = switch (family) {
      RouteTextureFamily.trail => 6.0,
      RouteTextureFamily.track => 8.0,
      RouteTextureFamily.paved => 9.0,
    };
    final minimum = switch (family) {
      RouteTextureFamily.trail => 1.2,
      RouteTextureFamily.track => 1.5,
      RouteTextureFamily.paved => 1.6,
    };
    final width = math.max(minimum, baseWidth * scale);
    final classification = TrailClassification.fromMetadata(line.metadata);
    final outlineExtra = .8 + ((zoom - 9) / 5).clamp(0.0, 1.0);
    return RouteVisualStyle(
      family: family,
      width: width,
      outlineWidth: width + outlineExtra,
      fallbackColor: switch (family) {
        RouteTextureFamily.trail => const Color(0xFFD2A563),
        RouteTextureFamily.track => const Color(0xFFAA7C49),
        RouteTextureFamily.paved => const Color(0xFF77736B),
      },
      outlineColor: switch (family) {
        RouteTextureFamily.trail => const Color(0xFF70512E),
        RouteTextureFamily.track => const Color(0xFF5E4933),
        RouteTextureFamily.paved => const Color(0xFF494842),
      },
      difficulty: classification.difficulty,
      access: classification.access,
      visibility: classification.visibility,
    );
  }

  Color? get difficultyColor => switch (difficulty) {
    TrailDifficulty.t1 => const Color(0xFF4F8540),
    TrailDifficulty.t2 => const Color(0xFF668E36),
    TrailDifficulty.t3 => const Color(0xFFD69A2D),
    TrailDifficulty.t4 => const Color(0xFFD26332),
    TrailDifficulty.t5 => const Color(0xFFB33D35),
    TrailDifficulty.t6 => const Color(0xFF7C2736),
    TrailDifficulty.unknown => null,
  };

  static RouteTextureFamily _family(LineFeature line) {
    if (line.kind == MapFeatureKind.trail) return RouteTextureFamily.trail;
    const paved = {
      'asphalt',
      'concrete',
      'concrete:plates',
      'paving_stones',
      'sett',
      'cobblestone',
    };
    return paved.contains(line.metadata.surface?.toLowerCase())
        ? RouteTextureFamily.paved
        : RouteTextureFamily.track;
  }
}
