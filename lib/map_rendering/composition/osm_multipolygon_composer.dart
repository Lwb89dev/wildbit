import 'package:latlong2/latlong.dart';

import 'geographic_ring_topology.dart';

/// A member way of an OSM multipolygon relation. The role is normally
/// `outer` or `inner`; unknown roles are rejected rather than guessed.
class MultipolygonMember {
  const MultipolygonMember({required this.role, required this.points});

  final String role;
  final List<LatLng> points;
}

class MultipolygonPolygon {
  const MultipolygonPolygon({required this.outer, required this.holes});

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

class MultipolygonComposition {
  const MultipolygonComposition({required this.polygons, required this.issues});

  final List<MultipolygonPolygon> polygons;
  final List<String> issues;

  bool get isValid => polygons.isNotEmpty && issues.isEmpty;

  /// True only when all usable rings were assembled without a topology issue.
  /// Callers use this to decide whether it is safe to suppress standalone
  /// member ways from the same Overpass response.
  bool get isComplete => isValid;
}

/// Joins OSM multipolygon member ways by their exact geographic endpoints.
///
/// OSM is allowed to split one boundary into several ways and to reverse the
/// direction of any member. Joining here keeps that topology out of the
/// renderer and prevents a relation from being painted as disconnected
/// triangles or as a solid lake over an island.
abstract final class OsmMultipolygonComposer {
  static MultipolygonComposition compose(Iterable<MultipolygonMember> members) {
    final issues = <String>[];
    final memberList = members.toList(growable: false);
    if (memberList.any(
      (member) => member.role != 'outer' && member.role != 'inner',
    )) {
      issues.add('multipolygon contains an unsupported member role');
    }
    if (memberList.any((member) => member.points.length < 2)) {
      issues.add('multipolygon contains a member without usable geometry');
    }
    final outer = _closedRings(
      memberList.where((member) => member.role == 'outer'),
      issues,
      'outer',
    );
    final inner = _closedRings(
      memberList.where((member) => member.role == 'inner'),
      issues,
      'inner',
    );
    final holesByOuter = <int, List<List<LatLng>>>{};
    for (final candidate in inner) {
      if (outer.any(
        (outerRing) =>
            GeographicRingTopology.ringsIntersect(outerRing, candidate),
      )) {
        issues.add('an inner ring touches or crosses an outer ring');
        continue;
      }
      final owners =
          [
            for (var index = 0; index < outer.length; index++)
              if (GeographicRingTopology.contains(
                outer[index],
                candidate.first,
              ))
                index,
          ]..sort(
            (a, b) => GeographicRingTopology.area(
              outer[a],
            ).compareTo(GeographicRingTopology.area(outer[b])),
          );
      if (owners.isEmpty) {
        issues.add('one or more inner rings are outside every outer ring');
      } else {
        final holes = holesByOuter[owners.first] ??= [];
        final conflicts = holes.any(
          (hole) =>
              GeographicRingTopology.ringsIntersect(hole, candidate) ||
              GeographicRingTopology.contains(hole, candidate.first) ||
              GeographicRingTopology.contains(candidate, hole.first),
        );
        if (conflicts) {
          issues.add('inner multipolygon rings overlap or contain each other');
        } else {
          holes.add(candidate);
        }
      }
    }
    final polygons = <MultipolygonPolygon>[];
    for (var index = 0; index < outer.length; index++) {
      final ring = outer[index];
      final holes = holesByOuter[index] ?? const <List<LatLng>>[];
      polygons.add(
        MultipolygonPolygon(
          outer: List<LatLng>.unmodifiable(ring),
          holes: List<List<LatLng>>.unmodifiable([
            for (final hole in holes) List<LatLng>.unmodifiable(hole),
          ]),
        ),
      );
    }
    return MultipolygonComposition(
      polygons: List.unmodifiable(polygons),
      issues: List.unmodifiable(issues),
    );
  }

  static List<List<LatLng>> _closedRings(
    Iterable<MultipolygonMember> members,
    List<String> issues,
    String role,
  ) {
    final pending = [
      for (final member in members)
        if (member.points.length >= 2) _WorkingWay(member.points),
    ];
    final rings = <List<LatLng>>[];
    while (pending.isNotEmpty) {
      final first = pending.removeAt(0);
      final ring = <LatLng>[...first.points];
      var closed = GeographicRingTopology.sameCoordinate(ring.first, ring.last);
      while (!closed) {
        final endpoint = ring.last;
        final matches = <({int index, bool reversed})>[];
        for (var index = 0; index < pending.length; index++) {
          final candidate = pending[index].points;
          final matchesFirst = GeographicRingTopology.sameCoordinate(
            endpoint,
            candidate.first,
          );
          final matchesLast = GeographicRingTopology.sameCoordinate(
            endpoint,
            candidate.last,
          );
          if (matchesFirst || matchesLast) {
            matches.add((index: index, reversed: !matchesFirst && matchesLast));
          }
        }
        if (matches.isEmpty) break;
        if (matches.length != 1) {
          issues.add('$role multipolygon endpoint is ambiguous');
          break;
        }
        final match = matches.single;
        final next = pending.removeAt(match.index).points;
        final ordered = match.reversed ? next.reversed.toList() : next;
        ring.addAll(ordered.skip(1));
        closed = GeographicRingTopology.sameCoordinate(ring.first, ring.last);
      }
      if (!closed || ring.length < 4) {
        issues.add('$role multipolygon ring is not closed');
        continue;
      }
      final normalized = _withoutRepeatedClosingPoint(ring);
      if (GeographicRingTopology.hasRepeatedVertex(normalized)) {
        issues.add('$role multipolygon ring repeats an interior vertex');
        continue;
      }
      if (GeographicRingTopology.selfIntersects(normalized)) {
        issues.add('$role multipolygon ring self-intersects');
        continue;
      }
      if (GeographicRingTopology.area(normalized) < 1e-12) {
        issues.add('$role multipolygon ring has no usable area');
        continue;
      }
      rings.add(normalized);
    }
    return rings;
  }

  static List<LatLng> _withoutRepeatedClosingPoint(List<LatLng> ring) {
    if (ring.length > 1 &&
        GeographicRingTopology.sameCoordinate(ring.first, ring.last)) {
      return ring.sublist(0, ring.length - 1);
    }
    return ring;
  }
}

class _WorkingWay {
  const _WorkingWay(this.points);

  final List<LatLng> points;
}
