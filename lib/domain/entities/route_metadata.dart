/// OSM attributes describing a route segment.
///
/// These are observations from map data, not safety guarantees. Null means
/// unknown/unmapped and must never be interpreted as a favourable value by a
/// routing or safety decision.
class RouteMetadata {
  const RouteMetadata({
    this.osmWayId,
    this.bridgeTag,
    this.bridgeStructure,
    this.surface,
    this.widthMeters,
    this.sacScale,
    this.trailVisibility,
    this.access,
    this.footAccess,
  });

  final String? osmWayId;
  final String? bridgeTag;
  final String? bridgeStructure;
  final String? surface;
  final double? widthMeters;
  final String? sacScale;
  final String? trailVisibility;
  final String? access;
  final String? footAccess;

  /// Only an explicit affirmative OSM bridge value allows bridge artwork.
  /// Unknown values deliberately do not become a passable-looking bridge.
  bool get hasConfirmedBridge => bridgeTag == 'yes';

  static RouteMetadata fromOsmTags(Map<String, String> tags, {String? wayId}) {
    return RouteMetadata(
      osmWayId: wayId,
      bridgeTag: _value(tags['bridge']),
      bridgeStructure: _value(tags['bridge:structure']),
      surface: _value(tags['surface']),
      widthMeters: _parseMeters(tags['width']),
      sacScale: _value(tags['sac_scale']),
      trailVisibility: _value(tags['trail_visibility']),
      access: _value(tags['access']),
      footAccess: _value(tags['foot']),
    );
  }

  static String? _value(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  /// Parses only an unambiguous metre measurement: `1.2` or `1.2 m`.
  /// Feet, ranges, approximations and free-form values stay unknown rather
  /// than being guessed incorrectly for a safety-relevant display.
  static double? _parseMeters(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:m)?$').firstMatch(value);
    if (match == null) return null;
    final meters = double.tryParse(match.group(1)!);
    return meters != null && meters > 0 ? meters : null;
  }
}
