import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/map_rendering/composition/shelter_sprite_metrics.dart';

void main() {
  test('alpine huts are larger but share the same ground anchor', () {
    const foot = Offset(120, 200);
    final alpine = ShelterSpriteMetrics.destination(
      foot: foot,
      markerSize: 60,
      imageWidth: 48,
      imageHeight: 48,
      shelterType: 'alpine_hut',
    );
    final bivouac = ShelterSpriteMetrics.destination(
      foot: foot,
      markerSize: 60,
      imageWidth: 32,
      imageHeight: 32,
      shelterType: 'wilderness_hut',
    );
    expect(alpine.height, greaterThan(bivouac.height));
    expect(alpine.center.dx, closeTo(foot.dx, .001));
    expect(bivouac.center.dx, closeTo(foot.dx, .001));
    expect(alpine.bottom, closeTo(foot.dy, .001));
    expect(bivouac.bottom, closeTo(foot.dy, .001));
  });

  test('alpine source crop removes transparent grounding rows', () {
    final source = ShelterSpriteMetrics.sourceRect(
      imageWidth: 48,
      imageHeight: 48,
      shelterType: 'alpine_hut',
    );
    expect(source.width, 48);
    expect(source.height, 38);
    final bivouac = ShelterSpriteMetrics.sourceRect(
      imageWidth: 32,
      imageHeight: 32,
      shelterType: 'wilderness_hut',
    );
    expect(bivouac.height, 32);
  });
}
