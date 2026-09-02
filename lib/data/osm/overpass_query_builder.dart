import '../../domain/entities/geo_bounds.dart';

/// Builds Overpass QL queries for the OSM tags WildBit turns into map
/// features. Kept isolated so the tag list can grow without touching the
/// HTTP or parsing code.
abstract final class OverpassQueryBuilder {
  static String forBounds(GeoBounds bounds) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';

    final clauses = <String>[
      'way["natural"="wood"]($bbox);',
      'way["landuse"="forest"]($bbox);',
      'way["landuse"="meadow"]($bbox);',
      'way["natural"="grassland"]($bbox);',
      'way["leisure"="park"]($bbox);',
      'way["natural"="water"]($bbox);',
      'way["waterway"="riverbank"]($bbox);',
      'relation["type"="multipolygon"]["natural"="water"]($bbox);',
      'relation["type"="multipolygon"]["waterway"="riverbank"]($bbox);',
      'relation["type"="multipolygon"]["natural"="wood"]($bbox);',
      'relation["type"="multipolygon"]["landuse"="forest"]($bbox);',
      'relation["type"="multipolygon"]["landuse"="meadow"]($bbox);',
      'relation["type"="multipolygon"]["leisure"="park"]($bbox);',
      'way["waterway"~"^(river|stream|canal|ditch)"]($bbox);',
      'way["natural"="coastline"]($bbox);',
      'way["natural"="bare_rock"]($bbox);',
      'way["natural"="scree"]($bbox);',
      'way["natural"="glacier"]($bbox);',
      'way["highway"~"^(path|footway|track|steps|bridleway|via_ferrata)\$"]($bbox);',
      'way["ford"]($bbox);',
      'way["highway"~"^(residential|service|unclassified|tertiary|secondary|primary)\$"]($bbox);',
      for (final selector in _poiSelectors) 'node$selector($bbox);',
    ];

    // `body` retains the ordered OSM node references for every way; `geom`
    // supplies the coordinates used for drawing. Both are required: geometry
    // alone is never used to infer a route connection by proximity.
    // Keep a slow public Overpass instance from blocking the first map paint
    // for minutes; the repository can retry another endpoint or refresh cache.
    // Route relations are metadata only. A separate `out body` prevents a
    // long-distance route relation from returning geometry far outside the
    // viewport; selected ways above remain the sole source of drawn lines.
    return '[out:json][timeout:12];(${clauses.join()});out body geom;'
        'relation["type"="route"]["route"~"^(hiking|foot)\$"]($bbox);'
        'out body;';
  }

  static const _poiSelectors = [
    '["tourism"="viewpoint"]',
    '["tourism"="alpine_hut"]',
    '["tourism"="wilderness_hut"]',
    '["amenity"="shelter"]',
    '["tourism"="information"]["information"="guidepost"]',
    '["tourism"="camp_site"]',
    '["amenity"="parking"]',
    '["natural"="spring"]',
    '["amenity"="drinking_water"]',
    '["natural"="peak"]',
    '["ford"]',
  ];

  /// Buildings and complex POIs share one optional context request. Keeping
  /// them out of the base query prevents a dense urban cell or multipolygon
  /// campsite from delaying trails, water and terrain.
  static String structuresForBounds(
    GeoBounds bounds, {
    bool includeBuildings = true,
  }) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';
    final poiClauses = <String>[
      for (final selector in _poiSelectors)
        for (final elementType in const ['way', 'relation'])
          '$elementType$selector($bbox);',
    ];
    // Put buildings and hiking structures in separate output statements. A
    // dense city can contain tens of thousands of footprints; limiting only
    // that decorative branch prevents it from delaying or truncating huts,
    // guideposts and campsites returned by the second branch.
    final buildings = includeBuildings
        ? 'way["building"]($bbox);out body geom 240;'
        : '';
    return '[out:json][timeout:10];$buildings'
        '(${poiClauses.join()});out body geom;';
  }

  static String treesForBounds(GeoBounds bounds) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';
    // `body` is required here: `tags` alone omits node latitude/longitude.
    // Individual trees are visual enrichment rather than route evidence.
    // The renderer itself can paint at most a few hundred point trees, so an
    // unbounded city/park response only wastes mobile bandwidth and parsing.
    return '[out:json][timeout:8];node["natural"="tree"]($bbox);out body 700;';
  }
}
