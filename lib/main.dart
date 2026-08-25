import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'data/test_data/test_region.dart';
import 'location/geolocator_location_service.dart';
import 'location/location_service.dart';
import 'location/simulated_location_service.dart';
import 'presentation/onboarding/key_recovery_gate.dart';
import 'services/security/database_key_manager.dart';

class _BitSplashGate extends StatefulWidget {
  const _BitSplashGate({required this.child});

  final Widget child;

  @override
  State<_BitSplashGate> createState() => _BitSplashGateState();
}

class _BitSplashGateState extends State<_BitSplashGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return const ColoredBox(
      color: Color(0xFF142A25),
      child: Center(
        child: Image(
          image: AssetImage('assets/icons/mascotte.png'),
          width: 280,
          height: 320,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

LocationService _buildLocationService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return GeolocatorLocationService();
  }
  // Desktop/dev builds have no real GPS hardware wired up: walk a fixed
  // path so Bit and the map can still be exercised end to end.
  return SimulatedLocationService(
    path: testRegionFeatures.lines
        .firstWhere((line) => line.name == 'Sentiero del Lago Alto')
        .points,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locationService = _buildLocationService();
  runApp(_KeyResolutionRoot(locationService: locationService));
}

/// Resolves the database key before anything else runs — the database must
/// open already encrypted, so the key can never be created (or read) later
/// than the database itself. Most launches resolve instantly from the
/// device's own cache; a reinstall/restore that carried over Nostr-link
/// metadata without the matching key (Keystore never survives an uninstall)
/// is routed through [KeyRecoveryGate] first instead of silently generating
/// a new key that couldn't open a restored backup.
class _KeyResolutionRoot extends StatefulWidget {
  const _KeyResolutionRoot({required this.locationService});

  final LocationService locationService;

  @override
  State<_KeyResolutionRoot> createState() => _KeyResolutionRootState();
}

class _KeyResolutionRootState extends State<_KeyResolutionRoot> {
  final _keyManager = DatabaseKeyManager();
  String? _databaseKey;
  bool _showRecoveryGate = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (await _keyManager.hasRecoverableIdentity()) {
      if (mounted) setState(() => _showRecoveryGate = true);
      return;
    }
    final key = await _keyManager.resolveKey();
    if (mounted) setState(() => _databaseKey = key);
  }

  @override
  Widget build(BuildContext context) {
    final key = _databaseKey;
    if (key != null) {
      return WildBitProviders(
        locationService: widget.locationService,
        databaseKey: key,
        child: _BitSplashGate(
          child: WildBitApp(locationService: widget.locationService),
        ),
      );
    }
    if (_showRecoveryGate) {
      return KeyRecoveryGate(
        keyManager: _keyManager,
        onKeyResolved: (key) => setState(() => _databaseKey = key),
      );
    }
    return const ColoredBox(color: Color(0xFF142A25));
  }
}
