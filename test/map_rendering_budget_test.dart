import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/performance/map_rendering_budget.dart';

void main() {
  tearDown(() => MapRenderingBudget.setMapInteracting(false));

  test('temporarily lowers decorative and route work during gestures', () {
    final normalDecorative = MapRenderingBudget.decorativeCount(
      15,
      overview: 4,
      close: 100,
    );
    final normalRoutes = MapRenderingBudget.routeMaximumPoints(
      _fakeTrail,
      16,
    );

    MapRenderingBudget.setMapInteracting(true);
    expect(
      MapRenderingBudget.decorativeCount(15, overview: 4, close: 100),
      lessThan(normalDecorative),
    );
    expect(
      MapRenderingBudget.routeMaximumPoints(_fakeTrail, 16),
      lessThan(normalRoutes),
    );

    MapRenderingBudget.setMapInteracting(false);
    expect(
      MapRenderingBudget.decorativeCount(15, overview: 4, close: 100),
      normalDecorative,
    );
    expect(MapRenderingBudget.mapInteracting, isFalse);
  });
}

// The budget only reads kind and route metadata; keeping this test focused on
// the public budget API avoids coupling it to a renderer widget.
const _fakeTrail = LineFeature(
  kind: MapFeatureKind.trail,
  points: [LatLng(46, 11), LatLng(46.001, 11.001)],
);
