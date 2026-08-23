import '../entities/saved_track.dart';

abstract interface class TrackRepository {
  /// Persists [track] (insert if `track.id == null`, replace otherwise) and
  /// returns its id.
  Future<int> saveTrack(SavedTrack track);

  Future<List<SavedTrack>> listTracks();

  Future<SavedTrack?> getTrack(int id);

  Future<void> deleteTrack(int id);
}
