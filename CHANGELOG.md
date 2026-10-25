# Changelog

All notable changes to WildBit are documented here.

## [0.1.4] - 2026-10-25

### Security and privacy

- Release builds no longer write diagnostics to the system log (map cell keys
  revealed the visited area); native GNSS code never logs coordinates.
- Weather requests send the position rounded to about 1 km instead of 11 m.
- Deleted tracks no longer leave their GPS points in the database: foreign keys
  are enforced, points are deleted explicitly, schema 6 purges points orphaned
  by earlier deletions, and `secure_delete` overwrites freed pages.
- GPX exports and database backups are staged in the cache directory and
  deleted after sharing; plaintext GPX exports left by earlier versions are
  removed. The picker's copy of an imported GPX file is cleared.
- Explore results are cached in the encrypted database instead of plaintext
  preferences; the old preference entry is deleted.
- Android backups are limited to preferences and the encrypted database.
  Cleartext network traffic is disabled explicitly.
- Amber: requests target Amber's package explicitly (an implicit intent could
  be claimed by another app, including the database key while linking), and
  content-provider answers are accepted only from Amber.
- Track events signed by Amber are verified (author, kind, content, tags, id
  and Schnorr signature) before they are published.
- The database key is validated before it reaches SQLite, and secure storage
  no longer wipes it after a transient Keystore error.
- Optional privacy zone: the share dialog can hide the first and last 200 m
  of a track (off by default; statistics stay complete).
- CI: signing secrets are scoped to the steps that use them, actions are
  pinned to commit SHAs, and checkout no longer persists the token.

### Fixed

- Publishing a track through Amber always failed: the signature was parsed as
  the signed event.
- Cancelling a request in Amber left the app waiting forever.
- A secure-storage failure at startup left a blank screen; a retry screen is
  shown instead, and no new key is ever generated over an existing database.
- Starting over after a restore left an unreadable database in place; it is
  now moved aside.
- Map artwork and Bit could disappear after Android memory pressure, because
  shared image handles were disposed by the image cache.
- Trails stayed untextured and simplified after a pan until the camera moved
  again.
- Voice guidance went silent for the rest of the session after an interrupted
  announcement; mapped trees and unnamed POIs no longer queue empty
  announcements.
- Nostr profile requests used a subscription id longer than NIP-01 allows;
  profile pictures load over HTTPS only.
- Building shadows apply to the buildings in view rather than the first ones
  of the whole data set.
- GPX import runs off the UI thread; import, export and sharing errors and the
  GPS notification are localized.

### Performance

- Pan frames reuse projected geometry through a single canvas translation in
  every pixel layer (trails and labels, water, waterways, coastlines, bridges,
  land cover, contours, buildings, POIs, trees, shrubs, flowers, recorded
  track and weather shadows). A widget test checks that panned frames are
  pixel-identical to a fresh projection.
- Per-frame work removed: feature signatures recomputed for unchanged data,
  building sorting with a centroid computed inside the comparator, footprint
  validation, POI asset scans, polygon areas recomputed while sorting water.
- Dashed trail overlays draw in one call per overlay; river bank tiles draw in
  one atlas call per river.
- Measured on a Galaxy S24 with the renderer profile harness (stress scene,
  medians of three runs): pan UI frame time 5.1–5.4 ms → 2.6 ms and p95 frame
  time 9.6–10.1 ms → 5.3 ms; fast pans p95 8.3–8.6 ms → 5.2 ms; zoom and
  rotation p95 8.3–8.8 ms → 5.6 ms. The profile harness can now run every
  scene and motion unattended (`WILDBIT_AUTORUN_MATRIX`) and logs the results.

### Release notes

- Android version code: `5`.

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
