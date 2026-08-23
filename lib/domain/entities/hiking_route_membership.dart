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
  int get displayPriority => switch (network) {
    'iwn' => 0,
    'nwn' => 1,
    'rwn' => 2,
    'lwn' => 3,
    _ => 4,
  };
}
