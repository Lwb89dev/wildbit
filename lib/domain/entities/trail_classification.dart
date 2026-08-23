import 'route_metadata.dart';

/// Exact SAC mountain-hiking scale values mapped to their T1–T6 shorthand.
/// Unknown or malformed values deliberately remain [unknown].
enum TrailDifficulty {
  unknown(null, 0),
  t1('T1', 1),
  t2('T2', 2),
  t3('T3', 3),
  t4('T4', 4),
  t5('T5', 5),
  t6('T6', 6);

  const TrailDifficulty(this.label, this.level);

  final String? label;
  final int level;

  static TrailDifficulty fromSacScale(String? value) => switch (value) {
    'hiking' => t1,
    'mountain_hiking' => t2,
    'demanding_mountain_hiking' => t3,
    'alpine_hiking' => t4,
    'demanding_alpine_hiking' => t5,
    'difficult_alpine_hiking' => t6,
    _ => unknown,
  };
}

enum TrailAccessStatus { unknown, explicitlyAllowed, restricted }

enum TrailVisibilityStatus { unknown, visible, reduced, poor }

/// Conservative presentation-only interpretation of OSM route metadata.
/// It never upgrades missing data to a safe or accessible state.
class TrailClassification {
  const TrailClassification({
    required this.difficulty,
    required this.access,
    required this.visibility,
  });

  factory TrailClassification.fromMetadata(RouteMetadata metadata) {
    return TrailClassification(
      difficulty: TrailDifficulty.fromSacScale(metadata.sacScale),
      access: _access(metadata),
      visibility: _visibility(metadata.trailVisibility),
    );
  }

  final TrailDifficulty difficulty;
  final TrailAccessStatus access;
  final TrailVisibilityStatus visibility;

  static TrailAccessStatus _access(RouteMetadata metadata) {
    final access = metadata.access?.trim().toLowerCase();
    final foot = metadata.footAccess?.trim().toLowerCase();
    if (access == 'no' ||
        access == 'private' ||
        foot == 'no' ||
        foot == 'private') {
      return TrailAccessStatus.restricted;
    }
    if (const {'yes', 'designated', 'permissive'}.contains(foot) ||
        const {'yes', 'permissive'}.contains(access)) {
      return TrailAccessStatus.explicitlyAllowed;
    }
    return TrailAccessStatus.unknown;
  }

  static TrailVisibilityStatus _visibility(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'excellent' || 'good' => TrailVisibilityStatus.visible,
        'intermediate' || 'bad' => TrailVisibilityStatus.reduced,
        'horrible' || 'no' => TrailVisibilityStatus.poor,
        _ => TrailVisibilityStatus.unknown,
      };
}
