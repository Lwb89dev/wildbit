import 'package:latlong2/latlong.dart';

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
    final outer = _closedRings(
      members.where((member) => member.role == 'outer'),
      issues,
      'outer',
    );
    final inner = _closedRings(
      members.where((member) => member.role == 'inner'),
      issues,
      'inner',
    );
    final holesByOuter = <int, List<List<LatLng>>>{};
    for (final candidate in inner) {
      final owners = [
        for (var index = 0; index < outer.length; index++)
          if (_contains(outer[index], candidate.first)) index,
      ]..sort((a, b) => _area(outer[a]).compareTo(_area(outer[b])));
      if (owners.isEmpty) {
        issues.add('one or more inner rings are outside every outer ring');
      } else {
        (holesByOuter[owners.first] ??= []).add(candidate);
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
      var closed = _same(ring.first, ring.last);
      while (!closed) {
        final endpoint = ring.last;
        var found = -1;
        var reversed = false;
        for (var index = 0; index < pending.length; index++) {
          final candidate = pending[index].points;
          if (_same(endpoint, candidate.first)) {
            found = index;
            break;
          }
          if (_same(endpoint, candidate.last)) {
            found = index;
            reversed = true;
            break;
          }
        }
        if (found < 0) break;
        final next = pending.removeAt(found).points;
        final ordered = reversed ? next.reversed.toList() : next;
        ring.addAll(ordered.skip(1));
        closed = _same(ring.first, ring.last);
      }
      if (!closed || ring.length < 4) {
        issues.add('$role multipolygon ring is not closed');
        continue;
      }
      final normalized = _withoutRepeatedClosingPoint(ring);
      if (_hasRepeatedVertex(normalized)) {
        issues.add('$role multipolygon ring repeats an interior vertex');
        continue;
      }
      if (_selfIntersects(normalized)) {
        issues.add('$role multipolygon ring self-intersects');
        continue;
      }
      rings.add(normalized);
    }
    return rings;
  }

  static List<LatLng> _withoutRepeatedClosingPoint(List<LatLng> ring) {
    if (ring.length > 1 && _same(ring.first, ring.last)) {
      return ring.sublist(0, ring.length - 1);
    }
    return ring;
  }

  static bool _same(LatLng a, LatLng b) =>
      a.latitude.toStringAsFixed(8) == b.latitude.toStringAsFixed(8) &&
      a.longitude.toStringAsFixed(8) == b.longitude.toStringAsFixed(8);

  static bool _contains(List<LatLng> polygon, LatLng point) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          (a.latitude > point.latitude) != (b.latitude > point.latitude);
      if (!crosses) continue;
      final longitude =
          (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (point.longitude < longitude) inside = !inside;
    }
    return inside;
  }

  static double _area(List<LatLng> polygon) {
    var area = 0.0;
    for (var index = 0; index < polygon.length; index++) {
      final current = polygon[index];
      final next = polygon[(index + 1) % polygon.length];
      area +=
          current.longitude * next.latitude - next.longitude * current.latitude;
    }
    return area.abs();
  }

  static bool _hasRepeatedVertex(List<LatLng> ring) {
    final seen = <String>{};
    for (final point in ring) {
      final key =
          '${point.latitude.toStringAsFixed(8)},${point.longitude.toStringAsFixed(8)}';
      if (!seen.add(key)) return true;
    }
    return false;
  }

  /// Rejects bow-tie and other self-crossing rings before they reach a
  /// PathFillType.evenOdd canvas. Adjacent segments are allowed to share
  /// their endpoint; all other intersections make the OSM relation unsafe to
  /// fill because the intended land/water topology is ambiguous.
  static bool _selfIntersects(List<LatLng> ring) {
    if (ring.length < 4) return false;
    for (var first = 0; first < ring.length; first++) {
      final firstEnd = (first + 1) % ring.length;
      for (var second = first + 1; second < ring.length; second++) {
        final secondEnd = (second + 1) % ring.length;
        if (first == second ||
            firstEnd == second ||
            secondEnd == first) {
          continue;
        }
        if (_segmentsIntersect(
          ring[first],
          ring[firstEnd],
          ring[second],
          ring[secondEnd],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsIntersect(
    LatLng a,
    LatLng b,
    LatLng c,
    LatLng d,
  ) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    const epsilon = 1e-14;
    if ((abC > epsilon && abD < -epsilon || abC < -epsilon && abD > epsilon) &&
        (cdA > epsilon && cdB < -epsilon || cdA < -epsilon && cdB > epsilon)) {
      return true;
    }
    return abC.abs() <= epsilon && _onSegment(a, b, c) ||
        abD.abs() <= epsilon && _onSegment(a, b, d) ||
        cdA.abs() <= epsilon && _onSegment(c, d, a) ||
        cdB.abs() <= epsilon && _onSegment(c, d, b);
  }

  static double _orientation(LatLng a, LatLng b, LatLng c) {
    return (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
  }

  static bool _onSegment(LatLng a, LatLng b, LatLng point) {
    return point.longitude >=
            (a.longitude < b.longitude ? a.longitude : b.longitude) - 1e-12 &&
        point.longitude <=
            (a.longitude > b.longitude ? a.longitude : b.longitude) + 1e-12 &&
        point.latitude >=
            (a.latitude < b.latitude ? a.latitude : b.latitude) - 1e-12 &&
        point.latitude <=
            (a.latitude > b.latitude ? a.latitude : b.latitude) + 1e-12;
  }
}

class _WorkingWay {
  const _WorkingWay(this.points);

  final List<LatLng> points;
}
