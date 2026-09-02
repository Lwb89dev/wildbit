import 'package:latlong2/latlong.dart';

/// Bounded Overpass query for Explore.
///
/// This deliberately returns trail *candidates*, never a route proposal. The
/// complete OSM way/relation geometry is still required before navigation can
/// offer anything to a hiker.
abstract final class TrailQueryBuilder {
  static String nearby({
    required LatLng position,
    required double radiusKm,
    String query = '',
  }) {
    final radiusMeters = (radiusKm.clamp(1, 100) * 1000).round();
    final around =
        '(around:$radiusMeters,${position.latitude},${position.longitude})';
    final normalized = query.trim();
    final matcher = normalized.isEmpty
        ? null
        : _escapeOverpassRegex(normalized);
    const wayBase =
        'way["highway"~"^(path|footway|track|steps|bridleway|via_ferrata)\$"]';
    const routeBase = 'relation["type"="route"]["route"~"^(hiking|foot)\$"]';
    final wayClauses = matcher == null
        ? ['$wayBase$around;']
        : [
            '$wayBase["name"~"$matcher",i]$around;',
            '$wayBase["ref"~"$matcher",i]$around;',
          ];
    // `network` is optional in OSM. Requiring it excluded many CAI and local
    // hiking relations even though they are explicitly typed as hiking routes.
    final routeClauses = matcher == null
        ? ['$routeBase$around;']
        : [
            '$routeBase["name"~"$matcher",i]$around;',
            '$routeBase["ref"~"$matcher",i]$around;',
          ];
    return '''
[out:json][timeout:12];
(${wayClauses.join()});
out tags center 150;
(${routeClauses.join()});
out tags center 60;
''';
  }

  // Besides regex metacharacters, quotes must be escaped because this text is
  // inserted into an Overpass QL string literal.
  static String _escapeOverpassRegex(String value) => value.replaceAllMapped(
    RegExp(r'([\\^$.*+?()[\]{}|"])'),
    (match) => '\\${match[0]}',
  );
}
