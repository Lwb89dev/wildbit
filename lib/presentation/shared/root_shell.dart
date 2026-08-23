import 'package:flutter/material.dart';

import '../../location/location_service.dart';
import '../explore/explore_screen.dart';
import '../map/map_screen.dart';
import '../offline/offline_screen.dart';
import '../routes/routes_screen.dart';
import '../settings/settings_screen.dart';
import '../track/track_screen.dart';

/// Bottom-nav shell hosting the 6 main screens from the product brief.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final Set<int> _mountedPages = {0};
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapScreen(locationService: widget.locationService),
      ExploreScreen(locationService: widget.locationService),
      const TrackScreen(),
      const RoutesScreen(),
      OfflineScreen(locationService: widget.locationService),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var page = 0; page < _screens.length; page++)
            _mountedPages.contains(page)
                ? _screens[page]
                : const SizedBox.expand(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          _index = value;
          _mountedPages.add(value);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Esplora'),
          NavigationDestination(
            icon: Icon(Icons.fiber_manual_record),
            label: 'Traccia',
          ),
          NavigationDestination(icon: Icon(Icons.route), label: 'Percorsi'),
          NavigationDestination(
            icon: Icon(Icons.download_for_offline),
            label: 'Offline',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Impostazioni',
          ),
        ],
      ),
    );
  }
}
