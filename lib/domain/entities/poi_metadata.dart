import '../enums/poi_type.dart';

/// OSM observations attached to a point of interest.
///
/// Null always means unknown/unmapped. In particular, a natural spring is not
/// assumed to be drinkable unless OSM says so explicitly.
class PoiMetadata {
  const PoiMetadata({
    this.elevationMeters,
    this.access,
    this.drinkingWater,
    this.operatorName,
    this.openingHours,
    this.shelterType,
  });

  final double? elevationMeters;
  final String? access;
  final bool? drinkingWater;
  final String? operatorName;
  final String? openingHours;

  /// Exact OSM shelter classification used to select an honest silhouette.
  /// Examples: `alpine_hut`, `wilderness_hut`, and `shelter`.
  final String? shelterType;

  bool get hasMappedDetails =>
      elevationMeters != null ||
      access != null ||
      drinkingWater != null ||
      operatorName != null ||
      openingHours != null;

  static PoiMetadata fromOsmTags(
    Map<String, String> tags, {
    required PoiType type,
  }) {
    final explicitDrinkingWater = _parseOsmBoolean(tags['drinking_water']);
    return PoiMetadata(
      elevationMeters: _parseElevationMeters(tags['ele']),
      access: _value(tags['access'])?.toLowerCase(),
      drinkingWater:
          explicitDrinkingWater ??
          (type == PoiType.waterSource && tags['amenity'] == 'drinking_water'
              ? true
              : null),
      operatorName: _value(tags['operator']),
      openingHours: _value(tags['opening_hours']),
      shelterType: type == PoiType.shelter ? _shelterTypeFrom(tags) : null,
    );
  }

  static String? _shelterTypeFrom(Map<String, String> tags) {
    final tourism = tags['tourism'];
    if (tourism == 'alpine_hut' || tourism == 'wilderness_hut') {
      return tourism;
    }
    return tags['amenity'] == 'shelter' ? 'shelter' : null;
  }

  static String? _value(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool? _parseOsmBoolean(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'yes' || 'true' || '1' => true,
        'no' || 'false' || '0' => false,
        _ => null,
      };

  /// Accept only an unambiguous value expressed in metres. Lists, ranges,
  /// feet and descriptive text remain unknown instead of being guessed.
  static double? _parseElevationMeters(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(?:m)?$').firstMatch(value);
    if (match == null) return null;
    final parsed = double.tryParse(match.group(1)!);
    return parsed?.isFinite == true ? parsed : null;
  }
}
