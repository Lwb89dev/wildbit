import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildbit/domain/entities/geo_bounds.dart';
import 'package:wildbit/domain/entities/hiking_route_membership.dart';
import 'package:wildbit/domain/entities/hiking_trail.dart';
import 'package:wildbit/domain/entities/map_feature_collection.dart';
import 'package:wildbit/domain/repositories/map_data_repository.dart';
import 'package:wildbit/services/selected_route_controller.dart';

void main() {
  final trail = const HikingTrail(
    id: 'wmt-relation-1',
    name: 'Sentiero di Prova',
    position: LatLng(46.0, 11.0),
    route: HikingRouteMembership(relationId: '1', network: 'REG'),
  );
  final geometry = [
    for (var i = 0; i <= 10; i++) LatLng(46.0, 11.0 + i * 0.001),
  ];

  test('selecting a route computes its corridor and resets download state', () {
    final controller = SelectedRouteController(
      mapDataRepository: _FakeMapDataRepository(),
    );

    controller.select(trail, geometry);

    expect(controller.trail, same(trail));
    expect(controller.geometry, geometry);
    expect(controller.corridorCellCount, greaterThan(0));
    expect(controller.downloadState, RouteDownloadState.idle);
  });

  test('clearing drops the selection entirely', () {
    final controller = SelectedRouteController(
      mapDataRepository: _FakeMapDataRepository(),
    )..select(trail, geometry);

    controller.clear();

    expect(controller.trail, isNull);
    expect(controller.geometry, isNull);
    expect(controller.corridorCellCount, isNull);
  });

  test('a successful download fetches every corridor cell and finishes done', () async {
    final fake = _FakeMapDataRepository();
    final controller = SelectedRouteController(mapDataRepository: fake)
      ..select(trail, geometry);
    final expectedCells = controller.corridorCellCount!;

    await controller.startDownload();

    expect(fake.requestedBounds.length, expectedCells);
    expect(controller.downloadedCells, expectedCells);
    expect(controller.failedCells, 0);
    expect(controller.downloadState, RouteDownloadState.done);
  });

  test('a failing cell is counted but does not stop the rest', () async {
    final fake = _FakeMapDataRepository(failEveryOther: true);
    final controller = SelectedRouteController(mapDataRepository: fake)
      ..select(trail, geometry);
    final expectedCells = controller.corridorCellCount!;

    await controller.startDownload();

    expect(controller.downloadedCells + controller.failedCells, expectedCells);
    expect(controller.failedCells, greaterThan(0));
    expect(controller.downloadState, RouteDownloadState.failed);
  });

  test('starting a download while one is already running is a no-op', () async {
    final fake = _FakeMapDataRepository();
    final controller = SelectedRouteController(mapDataRepository: fake)
      ..select(trail, geometry);

    final first = controller.startDownload();
    final second = controller.startDownload();
    await Future.wait([first, second]);

    expect(fake.requestedBounds.length, controller.corridorCellCount);
  });
}

class _FakeMapDataRepository implements MapDataRepository {
  _FakeMapDataRepository({this.failEveryOther = false});

  final bool failEveryOther;
  final List<GeoBounds> requestedBounds = [];

  @override
  Future<MapFeatureCollection> loadFeatures(GeoBounds bounds) async {
    requestedBounds.add(bounds);
    if (failEveryOther && requestedBounds.length.isEven) {
      throw Exception('simulated Overpass failure');
    }
    return const MapFeatureCollection(areas: [], lines: [], pois: []);
  }
}
