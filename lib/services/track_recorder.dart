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
  factory TrackRecorderController({
    required LocationService locationService,
    required TrackRepository repository,
    WildBitVoiceService? voice,
  }) => TrackRecorderController._(locationService, repository, voice);

  TrackRecorderController._(
    this._locationService,
    this._repository,
    this._voice,
  );

  static const _distance = Distance();
  // Hiking tracks must not gain kilometres because a cold or reflected GNSS
  // fix briefly lands on another valley. These are deliberately conservative:
  // 75 m still accepts usable forest coverage, while 12 m/s leaves ample room
  // for a fast runner but rejects impossible jumps in a walking recorder.
  static const _maximumAccuracyMeters = 75.0;
  static const _maximumPlausibleSpeedMetersPerSecond = 12.0;

  final LocationService _locationService;
  final TrackRepository _repository;
  final WildBitVoiceService? _voice;
  StreamSubscription<GeoFix>? _subscription;
  int _subscriptionGeneration = 0;
  bool _isSaving = false;
  bool _disposed = false;

  RecorderState state = RecorderState.idle;
  final List<GeoFix> points = [];
  double distanceMeters = 0;
  double elevationGainMeters = 0;
  DateTime? _startedAt;
  Duration _pausedAccumulated = Duration.zero;
  DateTime? _pausedAt;

  bool get isSaving => _isSaving;

  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    final end = _pausedAt ?? DateTime.now();
    return end.difference(start) - _pausedAccumulated;
  }

  double get currentSpeedMetersPerSecond =>
      points.isEmpty ? 0 : (points.last.speedMetersPerSecond ?? 0);

  void start() {
    if (_disposed || _isSaving || state != RecorderState.idle) return;
    state = RecorderState.recording;
    points.clear();
    distanceMeters = 0;
    elevationGainMeters = 0;
    _startedAt = DateTime.now();
    _pausedAccumulated = Duration.zero;
    _pausedAt = null;
    _subscribeToLocation();
    _notifyListeners();
    unawaited(_voice?.announceTrackStarted());
  }

  void pause() {
    if (_disposed || _isSaving || state != RecorderState.recording) return;
    state = RecorderState.paused;
    _pausedAt = DateTime.now();
    // A pause must actually disconnect from GPS — not just freeze the
    // elapsed-time counter — otherwise the phone keeps polling
    // bestForNavigation-accuracy GPS (and silently keeps appending points to
    // the "paused" track) for as long as the app is left open, which is a
    // real battery drain if someone pauses and forgets about it.
    final subscription = _subscription;
    _subscription = null;
    _subscriptionGeneration++;
    unawaited(subscription?.cancel());
    _notifyListeners();
  }

  void resume() {
    if (_disposed || _isSaving || state != RecorderState.paused) return;
    state = RecorderState.recording;
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedAccumulated += DateTime.now().difference(pausedAt);
    }
    _pausedAt = null;
    _subscribeToLocation();
    _notifyListeners();
  }

  /// Stops recording and persists the session as a [SavedTrack], returning
  /// its id. Returns null if there was nothing worth saving.
  Future<int?> stopAndSave({required String name}) async {
    if (_disposed || _isSaving) return null;
    final wasRecording = state != RecorderState.idle;
    if (!wasRecording || points.length < 2) {
      await _cancelLocationSubscription();
      state = RecorderState.idle;
      _resetTiming();
      _notifyListeners();
      return null;
    }

    _isSaving = true;
    if (state == RecorderState.recording) _pausedAt = DateTime.now();
    state = RecorderState.paused;
    _notifyListeners();

    final startedAt = _startedAt;
    final duration = elapsed;
    try {
      await _cancelLocationSubscription();
      final track = SavedTrack(
        name: name,
        createdAt: startedAt ?? DateTime.now(),
        distanceMeters: distanceMeters,
        durationSeconds: duration.inSeconds,
        elevationGainMeters: elevationGainMeters,
        source: TrackSource.recorded,
        points: List.unmodifiable(points),
      );
      final id = await _repository.saveTrack(track);
      state = RecorderState.idle;
      _resetTiming();
      unawaited(_voice?.announceTrackSaved());
      return id;
    } finally {
      // On persistence failure the session deliberately remains paused, with
      // all points intact, so the user can retry instead of losing the hike.
      _isSaving = false;
      _notifyListeners();
    }
  }

  void discard() {
    if (_disposed || _isSaving) return;
    final subscription = _subscription;
    _subscription = null;
    _subscriptionGeneration++;
    unawaited(subscription?.cancel());
    state = RecorderState.idle;
    points.clear();
    distanceMeters = 0;
    elevationGainMeters = 0;
    _resetTiming();
    _notifyListeners();
  }

  void _subscribeToLocation() {
    final generation = ++_subscriptionGeneration;
    _subscription = _locationService.positionStream.listen((fix) {
      if (!_disposed && generation == _subscriptionGeneration) _onFix(fix);
    });
  }

  Future<void> _cancelLocationSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    _subscriptionGeneration++;
    await subscription?.cancel();
  }

  void _resetTiming() {
    _startedAt = null;
    _pausedAt = null;
    _pausedAccumulated = Duration.zero;
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  void _onFix(GeoFix fix) {
    // Stream cancellation is asynchronous. A fix already queued when the user
    // pauses/discards must never leak into a non-recording session.
    if (state != RecorderState.recording) return;
    if (!_acceptsFix(fix)) return;
    if (points.isNotEmpty) {
      distanceMeters += _distance.as(
        LengthUnit.Meter,
        points.last.position,
        fix.position,
      );
      final prevAltitude = points.last.altitudeMeters;
      final altitude = fix.altitudeMeters;
      if (prevAltitude != null && altitude != null && altitude > prevAltitude) {
        elevationGainMeters += altitude - prevAltitude;
      }
    }
    points.add(fix);
    _notifyListeners();
  }

  bool _acceptsFix(GeoFix fix) {
    final accuracy = fix.accuracyMeters;
    if (accuracy != null &&
        (!accuracy.isFinite || accuracy > _maximumAccuracyMeters)) {
      return false;
    }
    if (points.isEmpty) return true;

    final previous = points.last;
    final elapsedSeconds =
        fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (!elapsedSeconds.isFinite || elapsedSeconds <= 0) return false;
    final segmentMeters = _distance.as(
      LengthUnit.Meter,
      previous.position,
      fix.position,
    );
    return segmentMeters / elapsedSeconds <=
        _maximumPlausibleSpeedMetersPerSecond;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscriptionGeneration++;
    state = RecorderState.idle;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
