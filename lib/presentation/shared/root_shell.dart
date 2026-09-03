import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../location/location_service.dart';
import '../../map_rendering/assets/map_visual_asset_warmup.dart';
import '../explore/explore_screen.dart';
import '../map/map_screen.dart';
import '../routes/routes_screen.dart';
import '../settings/settings_screen.dart';
import '../track/track_screen.dart';

/// Bottom-nav shell hosting the five main product screens.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final Set<int> _mountedPages = {0};
  LatLng? _lastMapCenter;
  double? _lastMapZoom;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      ExploreScreen(locationService: widget.locationService),
      const TrackScreen(),
      const RoutesScreen(),
      const SettingsScreen(),
    ];
    // Decode the compact, repeatedly used pixel artwork while the first map
    // frame is already visible. This is deliberately not a full renderer
    // prebuild: map GPU targets must remain releasable outside the Map tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(MapVisualAssetWarmup.warmup(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          // The Canvas compositor owns several GPU render targets. Unlike the
          // lighter product pages it is intentionally unmounted outside the
          // map tab; its camera is restored and already loaded OSM cells are
          // retained by the in-memory/data cache when appropriate.
          if (_index == 0)
            MapScreen(
              locationService: widget.locationService,
              initialCenter: _lastMapCenter,
              initialZoom: _lastMapZoom,
              onViewportSnapshot: (center, zoom) {
                _lastMapCenter = center;
                _lastMapZoom = zoom;
              },
            )
          else
            const SizedBox.expand(),
          for (var page = 1; page < 5; page++)
            _mountedPages.contains(page)
                ? TickerMode(enabled: page == _index, child: _screens[page - 1])
                : const SizedBox.expand(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
            _mountedPages.add(value);
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Esplora'),
          NavigationDestination(
            icon: Icon(Icons.fiber_manual_record),
            label: 'Traccia',
          ),
          NavigationDestination(icon: Icon(Icons.route), label: 'Percorsi'),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Impostazioni',
          ),
        ],
      ),
    );
  }
}
