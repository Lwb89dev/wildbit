import 'dart:async';

/// Typed HTTP failure retained across map and Explore requests, so cooldown
/// policy never depends on matching a human-readable exception string.
class OverpassHttpFailure implements Exception {
  const OverpassHttpFailure(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Overpass returned $statusCode';
}

/// Shared Overpass public-instance list and per-endpoint cooldown state.
///
/// A single app-wide singleton is intentional: whichever repository talks to
/// Overpass first backs off from a struggling endpoint (e.g. after a 502),
/// and every other caller — the map viewport fetcher, the Explore trail
/// search, anything added later — must respect that same cooldown instead of
/// hammering it again a second later from an independent retry loop. Public
/// Overpass instances are shared infrastructure, not ours to spam.
class OverpassEndpoints {
  OverpassEndpoints({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  static final OverpassEndpoints instance = OverpassEndpoints();

  static const all = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  final _cooldownUntil = <String, DateTime>{};
  final DateTime Function() _clock;

  bool isCoolingDown(String endpoint) {
    final until = _cooldownUntil[endpoint];
    return until != null && until.isAfter(_clock());
  }

  DateTime? cooldownUntil(String endpoint) => _cooldownUntil[endpoint];

  /// Records a failure for [endpoint]. Overloaded servers (429/5xx) get a
  /// longer cooldown than a generic network error, since they need more
  /// time to recover rather than a quick retry.
  void markFailed(String endpoint, {required bool serverOverloaded}) {
    final seconds = serverOverloaded ? 45 : 25;
    _cooldownUntil[endpoint] = _clock().add(Duration(seconds: seconds));
  }

  static bool isOverloadedFailure(Object error) =>
      error is TimeoutException ||
      error is OverpassHttpFailure &&
          (error.statusCode == 429 || error.statusCode >= 500);
}
