import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/osm/route_corridor.dart';
import '../domain/entities/geo_bounds.dart';
import '../domain/entities/hiking_trail.dart';
import '../domain/repositories/map_data_repository.dart';

enum RouteDownloadState { idle, downloading, done, failed }

/// Hands a curated route selected in Explore over to the Map screen: what to
/// draw, and — on explicit confirmation — which corridor of map cells to
/// prefetch for offline use.
///
/// Deliberately holds no persisted "is this route downloaded" record: a
/// prefetch is just a bulk, corridor-shaped trigger for the same map-data
/// cache the map already fills in as you walk/pan, so nothing new needs to
/// be tracked once the cells are in that cache. Depends on the
/// [MapDataRepository] interface rather than the concrete OSM
/// implementation so a download loop can be tested without real network
/// access.
class SelectedRouteController extends ChangeNotifier {
  SelectedRouteController({required this.mapDataRepository});

  final MapDataRepository mapDataRepository;

  HikingTrail? _trail;
  List<LatLng>? _geometry;
  List<GeoBounds>? _corridorCells;

  RouteDownloadState _downloadState = RouteDownloadState.idle;
  int _downloadedCells = 0;
  int _failedCells = 0;

  HikingTrail? get trail => _trail;
  List<LatLng>? get geometry => _geometry;
  RouteDownloadState get downloadState => _downloadState;
  int get downloadedCells => _downloadedCells;
  int get failedCells => _failedCells;

  /// Number of ~2km cells a corridor download would fetch. Null until a
  /// route is selected.
  int? get corridorCellCount => _corridorCells?.length;

  void select(HikingTrail trail, List<LatLng> geometry) {
    _trail = trail;
    _geometry = geometry;
    _corridorCells = RouteCorridor.cellsCovering(geometry);
    _downloadState = RouteDownloadState.idle;
    _downloadedCells = 0;
    _failedCells = 0;
    notifyListeners();
  }

  void clear() {
    _trail = null;
    _geometry = null;
    _corridorCells = null;
    _downloadState = RouteDownloadState.idle;
    _downloadedCells = 0;
    _failedCells = 0;
    notifyListeners();
  }

  /// Prefetches every corridor cell into the shared map-data cache so the
  /// route is renderable offline afterwards. Safe to call once; a second
  /// call while one is already running is a no-op.
  Future<void> startDownload() async {
    final cells = _corridorCells;
    if (cells == null || _downloadState == RouteDownloadState.downloading) {
      return;
    }
    _downloadState = RouteDownloadState.downloading;
    _downloadedCells = 0;
    _failedCells = 0;
    notifyListeners();

    for (final cell in cells) {
      try {
        await mapDataRepository.loadFeatures(cell);
        _downloadedCells++;
      } catch (_) {
        _failedCells++;
      }
      notifyListeners();
    }

    _downloadState = _failedCells == 0
        ? RouteDownloadState.done
        : RouteDownloadState.failed;
    notifyListeners();
  }
}
