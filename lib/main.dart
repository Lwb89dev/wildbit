import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'data/test_data/test_region.dart';
import 'location/geolocator_location_service.dart';
import 'location/location_service.dart';
import 'location/simulated_location_service.dart';
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
  // Resolved before runApp: the database must open already encrypted, so
  // the key can never be created (or read) later than the database itself.
  final databaseKey = await DatabaseKeyManager().resolveKey();

  runApp(
    WildBitProviders(
      locationService: locationService,
      databaseKey: databaseKey,
      child: _BitSplashGate(
        child: WildBitApp(locationService: locationService),
      ),
    ),
  );
}
