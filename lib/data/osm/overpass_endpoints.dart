/// Shared Overpass public-instance list and per-endpoint cooldown state.
///
/// A single app-wide singleton is intentional: whichever repository talks to
/// Overpass first backs off from a struggling endpoint (e.g. after a 502),
/// and every other caller — the map viewport fetcher, the Explore trail
/// search, anything added later — must respect that same cooldown instead of
/// hammering it again a second later from an independent retry loop. Public
/// Overpass instances are shared infrastructure, not ours to spam.
class OverpassEndpoints {
  OverpassEndpoints._();
  static final OverpassEndpoints instance = OverpassEndpoints._();

  static const all = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  final _cooldownUntil = <String, DateTime>{};

  bool isCoolingDown(String endpoint) {
    final until = _cooldownUntil[endpoint];
    return until != null && until.isAfter(DateTime.now());
  }

  DateTime? cooldownUntil(String endpoint) => _cooldownUntil[endpoint];

  /// Records a failure for [endpoint]. Overloaded servers (502/503) get a
  /// longer cooldown than a generic network error, since they need more
  /// time to recover rather than a quick retry.
  void markFailed(String endpoint, {required bool serverOverloaded}) {
    final seconds = serverOverloaded ? 45 : 25;
    _cooldownUntil[endpoint] = DateTime.now().add(Duration(seconds: seconds));
  }
}
