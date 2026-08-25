/// Conceptual cartographic layers WildBit understands, independent of how
/// they end up rendered (pixel-art style lives in map_rendering/).
enum MapFeatureKind {
  terrain,
  forest,
  meadow,
  park,
  water,
  waterway,
  coastline,
  mountainRock,
  snow,
  contourLine,
  building,
  road,
  trail,
  barrier,
}
