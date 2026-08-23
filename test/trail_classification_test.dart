import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/line_feature.dart';
import 'package:wildbit/domain/entities/route_metadata.dart';
import 'package:wildbit/domain/entities/trail_classification.dart';
import 'package:wildbit/domain/enums/map_feature_kind.dart';
import 'package:wildbit/map_rendering/composition/route_label_content.dart';

void main() {
  test('maps only exact SAC values to T1–T6', () {
    expect(TrailDifficulty.fromSacScale('hiking'), TrailDifficulty.t1);
    expect(TrailDifficulty.fromSacScale('mountain_hiking'), TrailDifficulty.t2);
    expect(
      TrailDifficulty.fromSacScale('demanding_mountain_hiking'),
      TrailDifficulty.t3,
    );
    expect(TrailDifficulty.fromSacScale('alpine_hiking'), TrailDifficulty.t4);
    expect(
      TrailDifficulty.fromSacScale('demanding_alpine_hiking'),
      TrailDifficulty.t5,
    );
    expect(
      TrailDifficulty.fromSacScale('difficult_alpine_hiking'),
      TrailDifficulty.t6,
    );
    expect(TrailDifficulty.fromSacScale('T2'), TrailDifficulty.unknown);
    expect(TrailDifficulty.fromSacScale(null), TrailDifficulty.unknown);
  });

  test('keeps access and visibility unknown unless explicitly mapped', () {
    final unknown = TrailClassification.fromMetadata(const RouteMetadata());
    expect(unknown.access, TrailAccessStatus.unknown);
    expect(unknown.visibility, TrailVisibilityStatus.unknown);

    final restricted = TrailClassification.fromMetadata(
      const RouteMetadata(footAccess: 'private', trailVisibility: 'horrible'),
    );
    expect(restricted.access, TrailAccessStatus.restricted);
    expect(restricted.visibility, TrailVisibilityStatus.poor);

    final allowed = TrailClassification.fromMetadata(
      const RouteMetadata(footAccess: 'designated', trailVisibility: 'good'),
    );
    expect(allowed.access, TrailAccessStatus.explicitlyAllowed);
    expect(allowed.visibility, TrailVisibilityStatus.visible);
  });

  test('labels mapped difficulty and gives restrictions absolute priority', () {
    const line = LineFeature(
      kind: MapFeatureKind.trail,
      name: 'Passo Alto',
      points: [LatLng(46, 11), LatLng(46.01, 11.01)],
      metadata: RouteMetadata(
        ref: '105',
        sacScale: 'demanding_mountain_hiking',
        access: 'private',
      ),
    );

    expect(RouteLabelContent.forLine(line, 11), isNull);
    expect(RouteLabelContent.forLine(line, 12)!.text, 'VIETATO · 105');
    final detailed = RouteLabelContent.forLine(line, 15)!;
    expect(detailed.text, 'VIETATO · 105 · T3 · Passo Alto');
    expect(detailed.priority, -1);
  });

  test('does not invent a technical label from missing metadata', () {
    const line = LineFeature(
      kind: MapFeatureKind.trail,
      points: [LatLng(46, 11), LatLng(46.01, 11.01)],
    );

    expect(RouteLabelContent.forLine(line, 18), isNull);
  });
}
