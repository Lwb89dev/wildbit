# Changelog

All notable changes to WildBit are documented here.

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
