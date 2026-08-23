/// 8-way compass direction used for Bit's on-map orientation.
enum Direction8 {
  n,
  ne,
  e,
  se,
  s,
  sw,
  w,
  nw;

  /// Bucket a compass bearing in degrees [0, 360) into the nearest of the
  /// 8 directions (0° = north, clockwise).
  static Direction8 fromBearingDegrees(double bearingDegrees) {
    final normalized = bearingDegrees % 360;
    final sector = ((normalized + 22.5) / 45).floor() % 8;
    return Direction8.values[sector];
  }

  /// Short lowercase code matching the sprite file naming (`walk_<code>_n.png`).
  String get spriteCode => name;
}
