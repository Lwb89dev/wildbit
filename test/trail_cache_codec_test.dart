import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:wildbit/data/osm/trail_cache_codec.dart';
import 'package:wildbit/domain/entities/hiking_trail.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';

void main() {
  test('round-trips trail metadata used by Explore safety labels', () {
    const trail = HikingTrail(
      id: 'osm-way-42',
      name: 'Sentiero cached',
      ref: 'E5',
      position: LatLng(46.071, 11.121),
      metadata: RouteMetadata(
        osmWayId: '42',
        highwayTag: 'path',
        access: 'yes',
        sacScale: 'hiking',
        trailVisibility: 'excellent',
      ),
    );

    final restored = TrailCacheCodec.decode(
      TrailCacheCodec.encode(const [trail]),
    );

    expect(restored, hasLength(1));
    expect(restored.single.position, trail.position);
    expect(restored.single.metadata.sacScale, 'hiking');
    expect(restored.single.eligibility.reasons, isNotEmpty);
  });
}
