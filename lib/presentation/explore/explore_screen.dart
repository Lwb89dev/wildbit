import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../data/repositories/osm_trail_repository.dart';
import '../../domain/entities/hiking_trail.dart';
import '../../domain/routing/route_eligibility_gate.dart';
import '../../location/location_service.dart';

/// Discover named hiking paths around the user, or narrow them by name.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static const _distance = Distance();
  final _searchController = TextEditingController();
  List<HikingTrail> _trails = const [];
  bool _isLoading = false;
  String? _error;
  String _activeQuery = '';
  LatLng? _position;
  double _radiusKm = 12;
  bool _usingCachedResults = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrails());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrails({String? query, bool forceRefresh = false}) async {
    final requestedQuery = query ?? _searchController.text;
    setState(() {
      _isLoading = true;
      _error = null;
      _usingCachedResults = false;
    });

    final fix = await widget.locationService.getCurrentPosition();
    if (!mounted) return;
    if (fix == null) {
      setState(() {
        _isLoading = false;
        _error = 'Serve la posizione per cercare sentieri vicino a te.';
      });
      return;
    }

    try {
      final repository = context.read<OsmTrailRepository>();
      final trails = await repository.findNearby(
        position: fix.position,
        query: requestedQuery,
        radiusKm: _radiusKm,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _position = fix.position;
        _activeQuery = requestedQuery.trim();
        _trails = trails;
        _isLoading = false;
        _usingCachedResults = repository.lastResultWasStale;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Non riesco a scaricare i sentieri ora. Riprova tra poco.';
      });
    }
  }

  void _showNearby() {
    _searchController.clear();
    _loadTrails(query: '');
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Esplora sentieri'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _isLoading
                ? null
                : () => _loadTrails(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sentieri escursionistici',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Consulta tratti OpenStreetMap entro ${_radiusKm.round()} km da te. Non sono percorsi consigliati.',
                  ),
                  if (_usingCachedResults) ...[
                    const SizedBox(height: 8),
                    const _LocalResultsNotice(),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.radar_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Raggio: ${_radiusKm.round()} km')),
                    ],
                  ),
                  Slider(
                    value: _radiusKm,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '${_radiusKm.round()} km',
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(() => _radiusKm = value),
                    onChangeEnd: (_) => _showNearby(),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _showNearby,
                          icon: const Icon(Icons.near_me),
                          label: const Text('Vicino a me'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) => _loadTrails(query: value),
                    decoration: InputDecoration(
                      hintText: 'Cerca un sentiero per nome',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Cancella',
                              onPressed: () {
                                _searchController.clear();
                                _showNearby();
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dati © OpenStreetMap contributors · ODbL',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildResults(context, position)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, LatLng? position) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.location_off_outlined,
        message: _error!,
        actionLabel: 'Riprova',
        onAction: _loadTrails,
      );
    }
    if (_trails.isEmpty) {
      final message = _activeQuery.isEmpty
          ? 'Nessun tratto OSM da verificare trovato nella zona.'
          : 'Nessun tratto OSM chiamato “$_activeQuery” nella tua zona.';
      return _MessageState(
        icon: Icons.hiking_outlined,
        message: message,
        actionLabel: 'Mostra vicini',
        onAction: _showNearby,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _trails.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final trail = _trails[index];
        final meters = position == null
            ? null
            : _distance.as(LengthUnit.Meter, position, trail.position);
        final eligibility = trail.eligibility;
        final blocked = eligibility.status == RouteProposalStatus.doNotOffer;
        final curated = trail.isCuratedRoute;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: blocked
                  ? Theme.of(context).colorScheme.errorContainer
                  : WildBitColors.oliveGreen,
              foregroundColor: blocked
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : WildBitColors.forestGreen,
              child: Icon(
                blocked
                    ? Icons.block
                    : curated
                    ? Icons.route
                    : Icons.warning_amber_rounded,
              ),
            ),
            title: Text(trail.name),
            subtitle: Text(
              [
                if (curated) _networkLabel(trail.route!.network),
                if (trail.ref != null && trail.ref != trail.name) trail.ref!,
                if (trail.lengthKm != null)
                  '${trail.lengthKm!.toStringAsFixed(1)} km di percorso',
                if (meters != null) _formatDistance(meters),
                blocked
                    ? 'Non proporre: ${eligibility.reasons.first}'
                    : 'Da verificare: ${eligibility.reasons.first}',
              ].whereType<String>().join(' · '),
            ),
          ),
        );
      },
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String? _networkLabel(String? network) => switch (network) {
    'iwn' => 'Rete internazionale',
    'nwn' => 'Rete nazionale',
    'rwn' => 'Rete regionale',
    'lwn' => 'Rete locale',
    _ => 'Percorso segnalato',
  };
}

class _LocalResultsNotice extends StatelessWidget {
  const _LocalResultsNotice();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_outlined, size: 17),
          SizedBox(width: 7),
          Expanded(
            child: Text('Risultati salvati localmente · verifica la data'),
          ),
        ],
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: WildBitColors.forestGreen),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
