import '../../domain/entities/geo_bounds.dart';

/// Builds Overpass QL queries for the OSM tags WildBit turns into map
/// features. Kept isolated so the tag list can grow without touching the
/// HTTP or parsing code.
abstract final class OverpassQueryBuilder {
  static String forBounds(GeoBounds bounds) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';

    final clauses = [
      'way["natural"="wood"]($bbox);',
      'way["landuse"="forest"]($bbox);',
      'way["landuse"="meadow"]($bbox);',
      'way["natural"="grassland"]($bbox);',
      'way["leisure"="park"]($bbox);',
      'way["natural"="water"]($bbox);',
      'way["waterway"="riverbank"]($bbox);',
      'way["waterway"~"^(river|stream|canal|ditch)"]($bbox);',
      'way["natural"="coastline"]($bbox);',
      'way["natural"="bare_rock"]($bbox);',
      'way["natural"="scree"]($bbox);',
      'way["natural"="glacier"]($bbox);',
      'way["highway"~"^(path|footway|track|steps)\$"]($bbox);',
      'way["highway"~"^(residential|service|unclassified|tertiary|secondary|primary)\$"]($bbox);',
      'node["tourism"="viewpoint"]($bbox);',
      'node["tourism"="alpine_hut"]($bbox);',
      'node["tourism"="wilderness_hut"]($bbox);',
      'node["amenity"="shelter"]($bbox);',
      'node["tourism"="information"]["information"="guidepost"]($bbox);',
      'node["tourism"="camp_site"]($bbox);',
      'node["amenity"="parking"]($bbox);',
      'node["natural"="spring"]($bbox);',
      'node["amenity"="drinking_water"]($bbox);',
      'node["natural"="peak"]($bbox);',
    ];

    // `body` retains the ordered OSM node references for every way; `geom`
    // supplies the coordinates used for drawing. Both are required: geometry
    // alone is never used to infer a route connection by proximity.
    // Keep a slow public Overpass instance from blocking the first map paint
    // for minutes; the repository can retry another endpoint or refresh cache.
    return '[out:json][timeout:12];(${clauses.join()});out body geom;';
  }

  /// Buildings are fetched separately because dense urban cells can contain
  /// thousands of them. Keeping them out of the route/vegetation response
  /// prevents one oversized payload from dropping trees and trails too.
  static String buildingsForBounds(GeoBounds bounds) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';
    return '[out:json][timeout:8];way["building"]($bbox);out body geom;';
  }

  static String treesForBounds(GeoBounds bounds) {
    final bbox =
        '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';
    // `body` is required here: `tags` alone omits node latitude/longitude.
    return '[out:json][timeout:8];node["natural"="tree"]($bbox);out body;';
  }
}
