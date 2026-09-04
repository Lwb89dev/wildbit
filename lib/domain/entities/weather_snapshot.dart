/// Weather data used by the renderer. It intentionally contains only the
/// small current-condition payload needed to choose a visual atmosphere; the
/// app never retains a forecast or a precise location history.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
    required this.weatherCode,
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.snowfallCm,
    required this.cloudCoverPercent,
    required this.visibilityMeters,
    required this.windSpeedKmh,
    required this.windDirectionDegrees,
    required this.isDay,
  });

  final double latitude;
  final double longitude;
  final DateTime fetchedAt;
  final int weatherCode;
  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
  final double snowfallCm;
  final double cloudCoverPercent;
  final double visibilityMeters;
  final double windSpeedKmh;
  final double windDirectionDegrees;
  final bool isDay;

  bool get isStorm => weatherCode >= 95;
  bool get isFog => weatherCode == 45 || weatherCode == 48;
  bool get isSnow => snowfallCm > 0 || (weatherCode >= 71 && weatherCode <= 86);
  bool get isRain =>
      rainMm > 0 ||
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82);

  /// Normalized precipitation amount for the particle system. Current API
  /// values are intentionally capped: a downpour should become denser, not
  /// allocate an unbounded number of particles.
  double get precipitationIntensity =>
      (precipitationMm / 6).clamp(0.0, 1.0).toDouble();

  double get snowIntensity => (snowfallCm / 3).clamp(0.0, 1.0).toDouble();

  double get cloudIntensity =>
      (cloudCoverPercent / 100).clamp(0.0, 1.0).toDouble();

  /// Visibility is in metres. Missing/invalid readings should not create a
  /// full white screen, so the fog contribution is deliberately bounded.
  double get fogIntensity {
    final visibilityFog = visibilityMeters.isFinite
        ? (1 - visibilityMeters / 9000).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return (isFog ? .7 : 0.0).clamp(visibilityFog, 1.0).toDouble();
  }

  /// Cloud and precipitation attenuate direct light. This is kept separate
  /// from the particle intensities so a cloudy dry day still casts a faint
  /// directional shadow.
  double get directLight =>
      isDay ? ((1 - cloudIntensity) * (isStorm ? .35 : 1)).clamp(0.08, 1.0) : 0;
}
