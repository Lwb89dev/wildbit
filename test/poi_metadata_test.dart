import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/domain/entities/poi_metadata.dart';
import 'package:wildbit/domain/enums/poi_type.dart';

void main() {
  test('does not assume that an untagged natural spring is drinkable', () {
    final metadata = PoiMetadata.fromOsmTags(const {
      'natural': 'spring',
    }, type: PoiType.waterSource);

    expect(metadata.drinkingWater, isNull);
  });

  test(
    'recognises explicit drinking-water semantics and negative override',
    () {
      final drinkingAmenity = PoiMetadata.fromOsmTags(const {
        'amenity': 'drinking_water',
      }, type: PoiType.waterSource);
      final explicitNo = PoiMetadata.fromOsmTags(const {
        'amenity': 'drinking_water',
        'drinking_water': 'no',
      }, type: PoiType.waterSource);

      expect(drinkingAmenity.drinkingWater, isTrue);
      expect(explicitNo.drinkingWater, isFalse);
    },
  );

  test('parses only unambiguous metre elevations', () {
    expect(
      PoiMetadata.fromOsmTags(const {
        'ele': '2134.5 m',
      }, type: PoiType.summit).elevationMeters,
      2134.5,
    );
    expect(
      PoiMetadata.fromOsmTags(const {
        'ele': '7000 ft',
      }, type: PoiType.summit).elevationMeters,
      isNull,
    );
    expect(
      PoiMetadata.fromOsmTags(const {
        'ele': '2100;2130',
      }, type: PoiType.summit).elevationMeters,
      isNull,
    );
  });
}
