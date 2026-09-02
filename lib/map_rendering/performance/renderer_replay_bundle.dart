import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../data/osm/feature_cache_codec.dart';
import '../../domain/entities/map_feature_collection.dart';

/// Versioned, network-free snapshot of one normalized OSM renderer scene.
///
/// The bundle intentionally contains [FeatureCacheCodec] output rather than a
/// raw Overpass response: it replays precisely the geometry the app renders
/// after tag classification and topology validation, without preserving a
/// query URL, device identity or any GPS history.
class RendererReplayBundle {
  const RendererReplayBundle({
    required this.capturedAt,
    required this.center,
    required this.zoom,
    required this.rotation,
    required this.features,
    this.label,
  });

  static const formatVersion = 1;
  static const fileExtension = 'wildbit-renderer-replay.json';
  static const maxEncodedBytes = 20 * 1024 * 1024;

  final DateTime capturedAt;
  final LatLng center;
  final double zoom;
  final double rotation;
  final MapFeatureCollection features;
  final String? label;

  String encode() {
    final result = jsonEncode({
      'formatVersion': formatVersion,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'label': label,
      'camera': {
        'lat': center.latitude,
        'lng': center.longitude,
        'zoom': zoom,
        'rotation': rotation,
      },
      'featuresJson': FeatureCacheCodec.encode(features),
    });
    if (utf8.encode(result).length > maxEncodedBytes) {
      throw const FormatException('Il replay renderer supera 20 MB');
    }
    return result;
  }

  static RendererReplayBundle decode(String encoded) {
    try {
      if (utf8.encode(encoded).length > maxEncodedBytes) {
        throw const FormatException('Il replay renderer supera 20 MB');
      }
      final raw = jsonDecode(encoded);
      if (raw is! Map) {
        throw const FormatException('Replay renderer non valido');
      }
      final map = raw.cast<String, dynamic>();
      if (map['formatVersion'] != formatVersion) {
        throw FormatException(
          'Versione replay non supportata: ${map['formatVersion']}',
        );
      }
      final camera = map['camera'];
      final featuresJson = map['featuresJson'];
      if (camera is! Map || featuresJson is! String) {
        throw const FormatException('Replay renderer incompleto');
      }
      final latitude = camera['lat'];
      final longitude = camera['lng'];
      final zoom = camera['zoom'];
      final rotation = camera['rotation'];
      final capturedAt = DateTime.tryParse(map['capturedAt']?.toString() ?? '');
      if (latitude is! num ||
          longitude is! num ||
          zoom is! num ||
          rotation is! num ||
          capturedAt == null ||
          latitude.abs() > 90 ||
          longitude.abs() > 180 ||
          zoom < 0 ||
          zoom > 24) {
        throw const FormatException('Camera replay non valida');
      }
      final rawLabel = map['label'];
      if (rawLabel != null && rawLabel is! String) {
        throw const FormatException('Etichetta replay non valida');
      }
      return RendererReplayBundle(
        capturedAt: capturedAt.toLocal(),
        center: LatLng(latitude.toDouble(), longitude.toDouble()),
        zoom: zoom.toDouble(),
        rotation: rotation.toDouble(),
        features: FeatureCacheCodec.decode(featuresJson),
        label: rawLabel,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      // The feature cache is intentionally decoded through its production
      // codec. Convert a bad internal field/type to one user-facing import
      // error instead of letting an unchecked cast escape the picker flow.
      throw const FormatException('Geometrie replay non valide');
    }
  }
}
