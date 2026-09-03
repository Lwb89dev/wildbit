/// An explicit membership of an OSM way in a hiking route relation.
///
/// Membership is accepted only from a `relation` member whose type is `way`
/// and whose numeric reference exactly matches the rendered way. It is map
/// metadata, not evidence that neighbouring downloaded segments connect.
class HikingRouteMembership {
  const HikingRouteMembership({
    required this.relationId,
    this.ref,
    this.name,
    this.network,
  });

  final String relationId;
  final String? ref;
  final String? name;
  final String? network;

  /// International/national routes win label space over regional/local ones.
  /// Accepts both OSM's own `network` tag values and Waymarked Trails'
  /// equivalent `group` codes (`INT`/`NAT`/`REG`/`AL2`-`AL4`/`LOC`), since a
  /// curated route can come from either source.
  int get displayPriority => switch (network) {
    'iwn' || 'INT' => 0,
    'nwn' || 'NAT' => 1,
    'rwn' || 'REG' => 2,
    'AL2' || 'AL3' || 'AL4' => 3,
    'lwn' || 'LOC' => 4,
    _ => 5,
  };
}
