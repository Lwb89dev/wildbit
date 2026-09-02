import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/data/test_data/renderer_stress_region.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/domain/enums/poi_type.dart';

void main() {
  test('local stress fixture retains the intended dense renderer workload', () {
    expect(
      rendererStressFeatures.pois.where((poi) => poi.type == PoiType.tree),
      hasLength(1380),
    );
    expect(
      rendererStressFeatures.areas.where(
        (area) => area.kind == MapFeatureKind.building,
      ),
      hasLength(322),
    );
    expect(
      rendererStressFeatures.lines.where(
        (line) => line.kind == MapFeatureKind.contourLine,
      ),
      hasLength(183),
    );
  });
}
