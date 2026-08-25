import 'hiking_route_membership.dart';

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
    this.ref,
    this.hikingRoutes = const [],
    this.highwayTag,
    this.trackType,
    this.waterwayTag,
    this.flowDirection,
    this.fordTag,
    this.tunnelTag,
    this.barrierTag,
    this.accessConditional,
    this.footConditional,
    this.openingHours,
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
  final String? ref;
  final List<HikingRouteMembership> hikingRoutes;
  final String? highwayTag;
  final String? trackType;
  final String? waterwayTag;

  /// Explicit `flow_direction`/`waterway:flow_direction` value. Null means
  /// that the OSM way order is the only available visual cue.
  final String? flowDirection;
  final String? fordTag;
  final String? tunnelTag;
  final String? barrierTag;
  final String? accessConditional;
  final String? footConditional;
  final String? openingHours;

  /// Only an explicit affirmative OSM bridge value allows bridge artwork.
  /// Unknown values deliberately do not become a passable-looking bridge.
  bool get hasConfirmedBridge => bridgeTag == 'yes';

  bool get hasConditionalAccess =>
      accessConditional != null ||
      footConditional != null ||
      openingHours != null;

  static RouteMetadata fromOsmTags(
    Map<String, String> tags, {
    String? wayId,
    List<HikingRouteMembership> hikingRoutes = const [],
  }) {
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
      ref: _value(tags['ref']),
      hikingRoutes: hikingRoutes,
      highwayTag: _value(tags['highway']),
      trackType: _value(tags['tracktype']),
      waterwayTag: _value(tags['waterway']),
      flowDirection: _flowDirection(tags),
      fordTag: _value(tags['ford']),
      tunnelTag: _value(tags['tunnel']),
      barrierTag: _value(tags['barrier']),
      accessConditional: _value(tags['access:conditional']),
      footConditional: _value(tags['foot:conditional']),
      openingHours: _value(tags['opening_hours']),
    );
  }

  static String? _value(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String? _flowDirection(Map<String, String> tags) {
    final value = _value(
      tags['flow_direction'] ?? tags['waterway:flow_direction'],
    )?.toLowerCase();
    return switch (value) {
      'forward' || 'downstream' => 'forward',
      'backward' || 'upstream' => 'backward',
      _ => null,
    };
  }

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
