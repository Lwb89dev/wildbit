import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/data/test_data/osm_replay_region.dart';
import 'package:wildbit/map_rendering/performance/renderer_replay_bundle.dart';

void main() {
  test('replays normalized OSM features with the exact camera state', () {
    final source = RendererReplayBundle(
      capturedAt: DateTime.utc(2026, 8, 28, 8, 30),
      center: const LatLng(46.0672, 11.1223),
      zoom: 15.75,
      rotation: 35,
      label: 'Cella alpina locale',
      features: osmReplayFeatures,
    );

    final restored = RendererReplayBundle.decode(source.encode());

    expect(restored.center.latitude, source.center.latitude);
    expect(restored.center.longitude, source.center.longitude);
    expect(restored.zoom, source.zoom);
    expect(restored.rotation, source.rotation);
    expect(restored.label, source.label);
    expect(restored.features.areas, hasLength(source.features.areas.length));
    expect(restored.features.lines, hasLength(source.features.lines.length));
    expect(restored.features.pois, hasLength(source.features.pois.length));
  });

  test('rejects malformed or incompatible replay snapshots', () {
    expect(
      () => RendererReplayBundle.decode('{"formatVersion": 99}'),
      throwsFormatException,
    );
    expect(
      () => RendererReplayBundle.decode('{"formatVersion": 1}'),
      throwsFormatException,
    );
    expect(
      () => RendererReplayBundle.decode('''
        {
          "formatVersion": 1,
          "capturedAt": "2026-08-28T08:30:00Z",
          "camera": {"lat": 46, "lng": 11, "zoom": 15, "rotation": 0},
          "featuresJson": "{\\"formatVersion\\":17,\\"areas\\":null}"
        }
      '''),
      throwsFormatException,
    );
  });
}
