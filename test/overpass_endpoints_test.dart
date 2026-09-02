import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/data/osm/overpass_endpoints.dart';

void main() {
  test('uses a deterministic cooldown clock for a failing endpoint', () {
    var now = DateTime.utc(2026, 9, 1, 12);
    final endpoints = OverpassEndpoints(clock: () => now);
    const endpoint = 'https://example.invalid/interpreter';

    endpoints.markFailed(endpoint, serverOverloaded: true);
    expect(endpoints.isCoolingDown(endpoint), isTrue);
    expect(
      endpoints.cooldownUntil(endpoint),
      now.add(const Duration(seconds: 45)),
    );

    now = now.add(const Duration(seconds: 46));
    expect(endpoints.isCoolingDown(endpoint), isFalse);
  });

  test('classifies public-server overloads without parsing error text', () {
    expect(
      OverpassEndpoints.isOverloadedFailure(const OverpassHttpFailure(429)),
      isTrue,
    );
    expect(
      OverpassEndpoints.isOverloadedFailure(const OverpassHttpFailure(502)),
      isTrue,
    );
    expect(
      OverpassEndpoints.isOverloadedFailure(const OverpassHttpFailure(404)),
      isFalse,
    );
    expect(
      OverpassEndpoints.isOverloadedFailure(TimeoutException('slow endpoint')),
      isTrue,
    );
  });
}
