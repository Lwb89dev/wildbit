import '../domain/entities/geo_fix.dart';

/// Abstraction over "where the user's position comes from". Kept separate
/// from networking/domain code so GPS access never depends on connectivity.
abstract interface class LocationService {
  /// Requests whatever OS permission is needed. Returns false if the user
  /// denies it; callers should degrade gracefully, never crash or silently
  /// pretend location works.
  Future<bool> ensurePermission();

  /// A live stream of position fixes. Must keep emitting with no network
  /// connection — GPS/GNSS is offline by nature.
  Stream<GeoFix> get positionStream;

  Future<GeoFix?> getCurrentPosition();
}
