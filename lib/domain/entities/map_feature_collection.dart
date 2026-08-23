import 'area_feature.dart';
import 'line_feature.dart';
import 'poi.dart';

/// Everything WildBit needs to render one region of the map, already split
/// into the conceptual layers described in the product brief. This is the
/// seam between raw geographic data (OSM today, test data for now) and the
/// pixel-art rendering pipeline.
class MapFeatureCollection {
  const MapFeatureCollection({
    required this.areas,
    required this.lines,
    required this.pois,
  });

  final List<AreaFeature> areas;
  final List<LineFeature> lines;
  final List<Poi> pois;

  /// Removes duplicate OSM features returned by neighbouring cache cells.
  /// Identity is used whenever it exists; geometry is never heuristically
  /// merged, preserving the distinction between two close real features.
  MapFeatureCollection deduplicated() {
    final areaIds = <String>{};
    final lineIds = <String>{};
    final poiIds = <String>{};
    return MapFeatureCollection(
      areas: [
        for (final area in areas)
          if (area.sourceId == null || areaIds.add(area.sourceId!)) area,
      ],
      lines: [
        for (final line in lines)
          if (line.metadata.osmWayId == null ||
              lineIds.add(line.metadata.osmWayId!))
            line,
      ],
      pois: [
        for (final poi in pois)
          if (poiIds.add(poi.id)) poi,
      ],
    );
  }
}
