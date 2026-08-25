import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:wildbit/domain/entities/geo_bounds.dart';
import 'package:wildbit/offline/offline_tile_cache.dart';
import 'package:wildbit/offline/offline_region_package.dart';
import 'package:wildbit/offline/offline_tile_plan.dart';

void main() {
  const bounds = GeoBounds(
    southWest: LatLng(46.067, 11.120),
    northEast: LatLng(46.071, 11.126),
  );

  test('selects unique slippy tiles across the requested zoom range', () {
    final tiles = OfflineTilePlan.forBounds(bounds, minZoom: 12, maxZoom: 13);
    expect(tiles, isNotEmpty);
    expect(tiles.map((tile) => tile.key).toSet(), hasLength(tiles.length));
    expect(tiles.every((tile) => tile.zoom == 12 || tile.zoom == 13), isTrue);
    expect(
      OfflineTilePlan.url(
        'https://example.test/{z}/{x}/{y}.png',
        tiles.first,
      ),
      endsWith('.png'),
    );
  });

  test('rejects a viewport whose tile budget is unsafe', () {
    expect(
      () => OfflineTilePlan.forBounds(
        const GeoBounds(
          southWest: LatLng(-60, -170),
          northEast: LatLng(60, 170),
        ),
        minZoom: 10,
        maxZoom: 14,
        maxTiles: 10,
      ),
      throwsStateError,
    );
  });

  test('local package is bounded around the current GPS fix', () {
    final package = OfflineRegionPackage.local(
      const LatLng(46.0679, 11.1211),
      radiusKm: 1,
    );
    expect(package.bounds.contains(const LatLng(46.0679, 11.1211)), isTrue);
    expect(package.bounds.northEast.latitude - package.bounds.southWest.latitude,
        closeTo(.018, .002));
    expect(package.name, contains('Pacchetto locale'));
  });

  test('downloads both base and hiking overlays and resumes from disk', () async {
    final root = await Directory.systemTemp.createTemp('wildbit_tiles_');
    addTearDown(() => root.delete(recursive: true));
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes(const [137, 80, 78, 71], 200);
    });
    final cache = OfflineTileCache(
      client: client,
      rootDirectory: () async => root,
      minZoom: 12,
      maxZoom: 12,
      maxTiles: 20,
    );
    final progress = <int>[];

    final first = await cache.downloadBounds(
      bounds,
      onProgress: (completed, _) => progress.add(completed),
    );
    final second = await cache.downloadBounds(bounds);

    expect(first, 2 * OfflineTilePlan.estimate(bounds, minZoom: 12, maxZoom: 12));
    expect(second, 0);
    expect(requests, first);
    expect(progress, isNotEmpty);
    expect(progress.last, 2 * OfflineTilePlan.estimate(bounds, minZoom: 12, maxZoom: 12));
  });
}
