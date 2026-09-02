import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/geo_fix.dart';
import 'package:wildbit/domain/entities/saved_track.dart';
import 'package:wildbit/domain/repositories/track_repository.dart';
import 'package:wildbit/location/location_service.dart';
import 'package:wildbit/services/track_recorder.dart';

void main() {
  test('recorder ignores degraded fixes and implausible GNSS jumps', () async {
    final location = _StreamLocationService();
    final recorder = TrackRecorderController(
      locationService: location,
      repository: _MemoryTrackRepository(),
    );
    addTearDown(() async {
      recorder.dispose();
      await location.dispose();
    });
    final started = DateTime.utc(2026, 9, 1, 8);

    recorder.start();
    location.add(_fix(46, 11, started, accuracy: 6));
    // A weak cold-start fix must never become the beginning of a false leg.
    location.add(
      _fix(
        46.01,
        11.01,
        started.add(const Duration(seconds: 3)),
        accuracy: 120,
      ),
    );
    // A precise-looking, but physically impossible 1 km jump is rejected too.
    location.add(
      _fix(46.01, 11, started.add(const Duration(seconds: 5)), accuracy: 5),
    );
    location.add(
      _fix(46.0001, 11, started.add(const Duration(seconds: 12)), accuracy: 5),
    );
    await Future<void>.delayed(Duration.zero);

    expect(recorder.points, hasLength(2));
    expect(recorder.distanceMeters, greaterThan(8));
    expect(recorder.distanceMeters, lessThan(15));
  });
}

GeoFix _fix(
  double latitude,
  double longitude,
  DateTime timestamp, {
  required double accuracy,
}) => GeoFix(
  position: LatLng(latitude, longitude),
  timestamp: timestamp,
  accuracyMeters: accuracy,
);

class _StreamLocationService implements LocationService {
  final _controller = StreamController<GeoFix>();

  void add(GeoFix fix) => _controller.add(fix);
  Future<void> dispose() => _controller.close();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<GeoFix?> getCurrentPosition() async => null;

  @override
  Stream<GeoFix> get positionStream => _controller.stream;
}

class _MemoryTrackRepository implements TrackRepository {
  @override
  Future<void> deleteTrack(int id) async {}

  @override
  Future<SavedTrack?> getTrack(int id) async => null;

  @override
  Future<List<SavedTrack>> listTracks() async => const [];

  @override
  Future<int> saveTrack(SavedTrack track) async => 1;
}
