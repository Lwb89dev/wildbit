import 'dart:math' as math;

/// Calculates sunrise and sunset times using the NOAA simplified solar
/// algorithm. Returns UTC [DateTime] values; null for rise/set in polar
/// day/night conditions where the sun never crosses the horizon.
class SunCalc {
  static ({DateTime? rise, DateTime? set}) sunTimes(double lat, double lng, DateTime date) {
    final doy = _dayOfYear(date);
    final b = 2 * math.pi * (doy - 1) / 365.0;

    final decl = 0.006918 -
        0.399912 * math.cos(b) +
        0.070257 * math.sin(b) -
        0.006758 * math.cos(2 * b) +
        0.000907 * math.sin(2 * b) -
        0.002697 * math.cos(3 * b) +
        0.001480 * math.sin(3 * b);

    final eot = 229.18 *
        (0.000075 +
            0.001868 * math.cos(b) -
            0.032077 * math.sin(b) -
            0.014615 * math.cos(2 * b) -
            0.040890 * math.sin(2 * b));

    final latRad = lat * math.pi / 180.0;
    final cosZenith = math.cos(90.833 * math.pi / 180.0);
    final cosHa = (cosZenith - math.sin(latRad) * math.sin(decl)) / (math.cos(latRad) * math.cos(decl));

    if (cosHa < -1 || cosHa > 1) return (rise: null, set: null);

    final ha = math.acos(cosHa) * 180.0 / math.pi;
    final solarNoon = 720.0 - 4.0 * lng - eot;
    final riseMin = solarNoon - 4.0 * ha;
    final setMin = solarNoon + 4.0 * ha;

    final base = DateTime.utc(date.year, date.month, date.day);
    return (
      rise: base.add(Duration(seconds: (riseMin * 60).round())),
      set: base.add(Duration(seconds: (setMin * 60).round())),
    );
  }

  static int _dayOfYear(DateTime d) => d.difference(DateTime.utc(d.year, 1, 1)).inDays + 1;
}
