import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/repositories/drift_offline_region_repository.dart';
import '../data/repositories/drift_track_repository.dart';
import '../data/repositories/osm_map_data_repository.dart';
import '../data/repositories/osm_trail_repository.dart';
import '../domain/repositories/offline_region_repository.dart';
import '../domain/repositories/track_repository.dart';
import '../location/location_service.dart';
import '../offline/offline_download_manager.dart';
import '../services/kokoro/wildbit_voice_service.dart';
import '../services/nostr/amber_signer_service.dart';
import '../services/nostr/track_share_service.dart';
import '../services/security/database_key_manager.dart';
import '../services/track_recorder.dart';
import '../storage/database.dart';
import 'theme/theme_provider.dart';

/// Wires up the app-wide dependency graph (database, repositories,
/// download manager, track recorder) via `provider`. Shared between
/// [main] and widget tests so both see the same object graph.
class WildBitProviders extends StatelessWidget {
  static const offlinePreview = bool.fromEnvironment(
    'WILDBIT_OFFLINE_PREVIEW',
    defaultValue: false,
  );
  static const mixedPreview = bool.fromEnvironment(
    'WILDBIT_MIXED_PREVIEW',
    defaultValue: false,
  );
  const WildBitProviders({
    super.key,
    required this.locationService,
    required this.databaseKey,
    required this.child,
  });

  final LocationService locationService;

  /// Resolved by [DatabaseKeyManager.resolveKey] before `runApp` — the
  /// database must be opened with this key already, so it can't be
  /// constructed lazily inside the provider tree the way the others are.
  final String databaseKey;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..init(),
        ),
        ChangeNotifierProvider<WildBitVoiceService>(
          create: (_) => WildBitVoiceService()..checkAndInit('it'),
        ),
        Provider<DatabaseKeyManager>(create: (_) => DatabaseKeyManager()),
        Provider<AmberSignerService>(create: (_) => AmberSignerService()),
        Provider<WildBitDatabase>(
          create: (_) => WildBitDatabase(databaseKey),
          dispose: (_, db) => db.close(),
        ),
        ProxyProvider3<
          WildBitDatabase,
          DatabaseKeyManager,
          AmberSignerService,
          TrackShareService
        >(
          update: (context, database, keyManager, amber, previous) =>
              TrackShareService(
                database: database,
                keyManager: keyManager,
                amber: amber,
              ),
        ),
        ProxyProvider<WildBitDatabase, TrackRepository>(
          update: (context, db, previous) => DriftTrackRepository(db),
        ),
        ChangeNotifierProxyProvider<TrackRepository, TrackRecorderController>(
          create: (context) => TrackRecorderController(
            locationService: locationService,
            repository: context.read<TrackRepository>(),
            voice: context.read<WildBitVoiceService>(),
          ),
          update: (context, repository, controller) => controller!,
        ),
        ProxyProvider<WildBitDatabase, OfflineRegionRepository>(
          update: (context, db, previous) => DriftOfflineRegionRepository(db),
        ),
        ProxyProvider<WildBitDatabase, OsmMapDataRepository>(
          update: (context, db, previous) => OsmMapDataRepository(
            database: db,
            offlinePreview: offlinePreview,
            mixedPreview: mixedPreview,
          ),
        ),
        Provider<OsmTrailRepository>(create: (_) => OsmTrailRepository()),
        ProxyProvider2<
          OfflineRegionRepository,
          OsmMapDataRepository,
          OfflineDownloadManager
        >(
          update: (context, areaRepository, mapDataRepository, previous) =>
              OfflineDownloadManager(
                areaRepository: areaRepository,
                mapDataRepository: mapDataRepository,
              ),
        ),
      ],
      child: child,
    );
  }
}
