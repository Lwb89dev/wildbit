import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../domain/entities/geo_fix.dart';
import '../domain/entities/saved_track.dart';
import '../domain/enums/track_source.dart';
import '../domain/repositories/track_repository.dart';
import '../location/location_service.dart';
import 'kokoro/wildbit_voice_service.dart';

enum RecorderState { idle, recording, paused }

/// Owns a live GPS recording session: accumulates fixes while
/// [state] is [RecorderState.recording] and derives running distance,
/// duration and elevation gain so the Track screen can show them live.
class TrackRecorderController extends ChangeNotifier {
  TrackRecorderController({
    required LocationService locationService,
    required TrackRepository repository,
    WildBitVoiceService? voice,
  })  : _locationService = locationService,
        _repository = repository,
        _voice = voice;

  static const _distance = Distance();

  final LocationService _locationService;
  final TrackRepository _repository;
  final WildBitVoiceService? _voice;
  StreamSubscription<GeoFix>? _subscription;

  RecorderState state = RecorderState.idle;
  final List<GeoFix> points = [];
  double distanceMeters = 0;
  double elevationGainMeters = 0;
  DateTime? _startedAt;
  Duration _pausedAccumulated = Duration.zero;
  DateTime? _pausedAt;

  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    final end = _pausedAt ?? DateTime.now();
    return end.difference(start) - _pausedAccumulated;
  }

  double get currentSpeedMetersPerSecond => points.isEmpty ? 0 : (points.last.speedMetersPerSecond ?? 0);

  void start() {
    if (state != RecorderState.idle) return;
    state = RecorderState.recording;
    points.clear();
    distanceMeters = 0;
    elevationGainMeters = 0;
    _startedAt = DateTime.now();
    _pausedAccumulated = Duration.zero;
    _subscription = _locationService.positionStream.listen(_onFix);
    notifyListeners();
    unawaited(_voice?.announceTrackStarted());
  }

  void pause() {
    if (state != RecorderState.recording) return;
    state = RecorderState.paused;
    _pausedAt = DateTime.now();
    notifyListeners();
  }

  void resume() {
    if (state != RecorderState.paused) return;
    state = RecorderState.recording;
    final pausedAt = _pausedAt;
    if (pausedAt != null) _pausedAccumulated += DateTime.now().difference(pausedAt);
    _pausedAt = null;
    notifyListeners();
  }

  /// Stops recording and persists the session as a [SavedTrack], returning
  /// its id. Returns null if there was nothing worth saving.
  Future<int?> stopAndSave({required String name}) async {
    await _subscription?.cancel();
    _subscription = null;
    final wasRecording = state != RecorderState.idle;
    state = RecorderState.idle;
    notifyListeners();

    if (!wasRecording || points.length < 2) return null;

    final track = SavedTrack(
      name: name,
      createdAt: _startedAt ?? DateTime.now(),
      distanceMeters: distanceMeters,
      durationSeconds: elapsed.inSeconds,
      elevationGainMeters: elevationGainMeters,
      source: TrackSource.recorded,
      points: List.unmodifiable(points),
    );
    final id = await _repository.saveTrack(track);
    unawaited(_voice?.announceTrackSaved());
    return id;
  }

  void discard() {
    _subscription?.cancel();
    _subscription = null;
    state = RecorderState.idle;
    points.clear();
    distanceMeters = 0;
    elevationGainMeters = 0;
    notifyListeners();
  }

  void _onFix(GeoFix fix) {
    if (points.isNotEmpty) {
      distanceMeters += _distance.as(LengthUnit.Meter, points.last.position, fix.position);
      final prevAltitude = points.last.altitudeMeters;
      final altitude = fix.altitudeMeters;
      if (prevAltitude != null && altitude != null && altitude > prevAltitude) {
        elevationGainMeters += altitude - prevAltitude;
      }
    }
    points.add(fix);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
