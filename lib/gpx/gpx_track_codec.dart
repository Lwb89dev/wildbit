import 'package:gpx/gpx.dart' as gpx;
import 'package:latlong2/latlong.dart';

import '../domain/entities/geo_fix.dart';
import '../domain/entities/saved_track.dart';
import '../domain/enums/track_source.dart';

/// Converts between WildBit's [SavedTrack] and the GPX 1.1 file format.
abstract final class GpxTrackCodec {
  static SavedTrack decode(String xmlContent, {required String fallbackName}) {
    final doc = gpx.GpxReader().fromString(xmlContent);
    final segment = doc.trks.firstOrNull?.trksegs.firstOrNull;
    final points = [
      for (final wpt in segment?.trkpts ?? const <gpx.Wpt>[])
        if (wpt.lat != null && wpt.lon != null)
          GeoFix(
            position: LatLng(wpt.lat!, wpt.lon!),
            timestamp: wpt.time ?? DateTime.now(),
            altitudeMeters: wpt.ele,
          ),
    ];

    return SavedTrack(
      name: doc.trks.firstOrNull?.name ?? doc.metadata?.name ?? fallbackName,
      createdAt: points.firstOrNull?.timestamp ?? DateTime.now(),
      distanceMeters: _totalDistance(points),
      durationSeconds: _durationSeconds(points),
      elevationGainMeters: _elevationGain(points),
      source: TrackSource.imported,
      points: points,
    );
  }

  static String encode(SavedTrack track) {
    final doc = gpx.Gpx()
      ..creator = 'WildBit'
      ..metadata = gpx.Metadata(name: track.name, time: track.createdAt)
      ..trks = [
        gpx.Trk(
          name: track.name,
          trksegs: [
            gpx.Trkseg(
              trkpts: [
                for (final point in track.points)
                  gpx.Wpt(
                    lat: point.position.latitude,
                    lon: point.position.longitude,
                    ele: point.altitudeMeters,
                    time: point.timestamp,
                  ),
              ],
            ),
          ],
        ),
      ];

    return gpx.GpxWriter().asString(doc, pretty: true);
  }

  static double _totalDistance(List<GeoFix> points) {
    if (points.length < 2) return 0;
    const distance = Distance();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distance.as(LengthUnit.Meter, points[i - 1].position, points[i].position);
    }
    return total;
  }

  static int _durationSeconds(List<GeoFix> points) {
    if (points.length < 2) return 0;
    return points.last.timestamp.difference(points.first.timestamp).inSeconds.abs();
  }

  static double _elevationGain(List<GeoFix> points) {
    var gain = 0.0;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1].altitudeMeters;
      final curr = points[i].altitudeMeters;
      if (prev == null || curr == null) continue;
      final delta = curr - prev;
      if (delta > 0) gain += delta;
    }
    return gain;
  }
}
