# Changelog

All notable changes to WildBit are documented here.

## [0.1.3] - 2026-09-18

### Fixed

- Prevented stale map, weather, Explore, route-download, GPS, voice, and Nostr
  callbacks from updating disposed or superseded screens.
- Added bounded response handling for public OSM, Overpass, Waymarked Trails,
  Nominatim, and weather requests.
- Preserved an in-progress track when saving fails, with a safe retry path.
- Fixed GPX imports with multiple segments and rejected invalid or unusable
  coordinates.
- Corrected antimeridian bounds, route corridors, map-cell coverage, and stale
  cache refresh behavior.
- Fixed empty/error states in Routes and Track details instead of leaving an
  endless spinner or opening an invalid map preview.

### Performance

- Limited broad map requests to nearby cells without materializing huge grids.
- Added bounded Waymarked Trails detail concurrency and coalesced weather
  refreshes.
- Cached selected-route preview geometry and stopped animating static weather
  overlays.
- Added transient map-cache eviction and lifecycle cleanup for HTTP clients,
  repositories, controllers, and map resources.

### Release notes

- Android version code: `4`.
- Split APKs are built for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- Release builds must be signed with the configured WildBit release keystore.

## [0.1.2] - 2026-09-04

### Added

- Added a persistent language selector with 27 supported locales, including
  English, Italian, all official European Union languages, Chinese, Japanese,
  and Russian.
- Localized navigation, onboarding, Explore, Map, Track, Routes, Settings,
  offline route downloads, POI details, backup, and Nostr sharing flows.
- Added locale-aware decimal formatting and English fallback for unsupported
  device languages.
- Added localized voice preview and automatic Kokoro voice selection based on
  the selected or system language.
- Added localization regression tests for supported locales, fallback behavior,
  decimal separators, and parameterized messages.

### Fixed

- Fixed the database key recovery gate so it can render and report errors before
  the main provider tree and application localization are initialized.
- Fixed map status, offline-download, renderer-replay, and onboarding messages
  that could remain in a different language from the selected UI language.
- Fixed the default locale resolution so unsupported system languages fall back
  to English instead of the first alphabetically sorted locale.
- Cleaned up analyzer warnings in the route download controller and map/routes
  screens.

### Release notes

- Android version code: `3`.
- Split APKs are built for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- Local builds use the debug signing key unless the documented
  `WILDBIT_RELEASE_*` signing variables are configured.
