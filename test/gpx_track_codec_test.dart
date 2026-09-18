import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/gpx/gpx_track_codec.dart';

void main() {
  test('imports every segment of the first GPX track in order', () {
    final track = GpxTrackCodec.decode('''
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Multi segment</name>
    <trkseg><trkpt lat="45.0" lon="9.0"/></trkseg>
    <trkseg><trkpt lat="45.1" lon="9.1"/></trkseg>
  </trk>
</gpx>
''', fallbackName: 'fallback');

    expect(track.name, 'Multi segment');
    expect(track.points, hasLength(2));
    expect(track.points.last.position.latitude, 45.1);
  });

  test('rejects a GPX without a usable track', () {
    expect(
      () => GpxTrackCodec.decode(
        '<gpx version="1.1" creator="test"></gpx>',
        fallbackName: 'empty',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
