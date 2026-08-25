# WildBit

WildBit is an experimental, privacy-first hiking application built with
Flutter. Its centrepiece is a pixel-art geographic map generated from
OpenStreetMap data: not a conventional raster map with a pixelation filter, but
an original semantic renderer that turns forests, meadows, water, trails,
buildings, and POIs into a small illustrated world.

Bit, the mascot, physically inhabits the scene. Bit walks with a trekking pole,
checks a map while the user is stationary, and is depth-sorted against trees
and rocks even when the map is rotated.

> [!WARNING]
> WildBit is currently an **alpha prototype**. It is not a certified navigation
> device and must not be used as the sole source for choosing or following a
> route. OSM data, GPS readings, accessibility, opening hours, drinking-water
> status, and trail conditions may be incomplete or outdated.

## Goals

- Render a readable hiking map with a consistent pixel-art language, without
  embedding proprietary third-party artwork or code.
- Obtain location fixes on Android without Google Play Services.
- Store tracks and offline areas locally in an encrypted database.
- Use open services and protocols: OpenStreetMap, Overpass, and Nostr.
- Keep geographic data, visual representation, and safety assessments
  separate.

The visual direction draws broad inspiration from JRPG dioramas and HD-2D.
WildBit is not affiliated with Square Enix and does not use its assets, maps,
or code.

## Feature status

| Area | Current status |
| --- | --- |
| Pixel-art renderer | Active on the main map; FlutterMap only handles the camera, projection, and gestures |
| Terrain and biomes | Grassland, forest, rock, snow, water, waterways, and coastline |
| Geometry | Trails, roads, bridges, buildings, shorelines, and a map scale |
| Objects | Trees, undergrowth, flowers, rocks, shelters, guideposts, and other POIs |
| Bit | Idle/walking animations, zoom-aware scale, and rotation-aware occlusion |
| Android GPS | Forced `LocationManager`, native cache, and GNSS fixes without Google APIs |
| Explore | OSM trail search by name or within a configurable radius up to 100 km |
| Track | Recording, pausing, saving, and hiking statistics |
| Offline | Map-based area selection and geographic feature caching; still experimental |
| POIs | Collision-aware labels, detail sheets, and conservative OSM metadata |
| Bit's voice | Optional offline Kokoro/ONNX synthesis with eSpeak NG phonemisation |
| Nostr | Optional Amber or nsec login and explicit track sharing |
| Automatic routing | Not available as trusted navigation; proposed segments require human verification |

The main sections are `Map`, `Explore`, `Track`, `Routes`, `Offline`,
and `Settings`.

## Map renderer

The main map does not display OSM raster tiles. Its pipeline is:

```text
OpenStreetMap / Overpass
        ↓
WildBit semantic parser and model
        ↓
versioned geographic cache
        ↓
FlutterMap projection
        ↓
Flutter Canvas composition + pixel-art sprites
```

Simplified composition order:

```text
terrain and water
→ shorelines, geology, and contour lines
→ biomes and buildings
→ trails, roads, and bridges
→ trees, rocks, and Bit with geographic depth
→ foreground vegetation
→ POIs, labels, and interface
```

Implemented principles:

- deterministic distribution: the same object retains its position and variant;
- stable geographic coordinates during pan, zoom, and rotation;
- nearest-neighbour asset rendering with no pixel blurring;
- trails and roads are not removed merely to simplify a zoom level;
- decorative detail and object size use separate LOD curves;
- objects are not generated inside water or within route corridors;
- Bit and tall objects are sorted using their projected, rotation-aware ground
  anchors;
- POI markers remain present, while only secondary labels may be omitted when
  space is unavailable;
- missing tags remain unknown: for example, a natural spring is not considered
  drinkable without an explicit OSM indication;
- hiking-route relations enrich only their exact OSM way members and never
  invent connections between nearby segments.

The offline-area selection screen is an intentional exception: it uses a
standard OSM map and the Waymarked Trails hiking overlay to make the download
area clear. That raster is not part of the main pixel-art renderer.

## Technology

- Flutter and Dart
- `flutter_map` and `latlong2`
- OpenStreetMap and public Overpass APIs
- Drift and SQLite3MultipleCiphers for the encrypted local database
- Android `LocationManager` through `geolocator` and a native channel
- Kokoro-82M through ONNX Runtime, with eSpeak NG
- Nostr, NIP-44, and external NIP-55 signing through Amber
- Provider for dependency wiring

## Repository layout

```text
android/                   Android integration and build
assets/
  icons/                   launcher icon and mascot
  map/mock/                renderer tiles and sprites
  sprites/bit/             Bit animation frames
docs/                      visual, technical, and performance specifications
lib/
  app/                     bootstrap, providers, and theme
  data/                    OSM parser, cache, and repositories
  domain/                  UI-independent entities and rules
  location/                real and simulated GNSS sources
  map_rendering/           compositors, Canvas layers, Bit, and budgets
  offline/                 area downloads and resumption
  presentation/            Flutter screens
  services/                voice, Nostr, recording, and security
  storage/                 Drift database
linux/                     desktop runner
test/                      unit, geometry, and widget tests
third_party/               local forks required by the build
```

## Development requirements

- Flutter with Dart `>= 3.12.2 < 4.0.0`
- Java 17
- Android SDK Platform 37 for Android builds
- A configured Linux desktop toolchain when using the Linux runner
- An Android device or emulator to test real permissions and GNSS behaviour

Check the environment:

```bash
flutter doctor -v
flutter pub get
```

## Running WildBit

### Linux with a simulated location

The desktop runner automatically uses a simulated route, so Bit can be tested
without GNSS hardware:

```bash
flutter run -d linux
```

### Complete offline preview

This mode does not query Overpass. It immediately loads a mock valley with
biomes, buildings, trails, trees, water, and POIs:

```bash
flutter run -d linux \
  --dart-define=WILDBIT_OFFLINE_PREVIEW=true \
  --dart-define=WILDBIT_MIXED_PREVIEW=true
```

### Isolated renderer laboratory

To work only on the static graphic scene:

```bash
flutter run -d linux -t lib/mock_preview_main.dart
```

### Android

With a device visible through ADB:

```bash
flutter devices
flutter run -d <device-id>
```

On first launch, onboarding explicitly requests location permission. A Nostr
identity is optional.

> [!IMPORTANT]
> Local release builds fall back to the debug signing key so smoke tests work
> without secrets. Distribution builds must provide the four
> `WILDBIT_RELEASE_*` signing variables; the manual GitHub Actions workflow
> also consumes `WILDBIT_RELEASE_KEYSTORE_B64` and produces a signed AAB.

## Tests and checks

Run the complete suite:

```bash
flutter test
```

Useful focused checks while developing the renderer:

```bash
dart analyze lib/map_rendering
flutter test test/map_geometry_rules_test.dart
flutter test test/projected_depth_order_test.dart
flutter test test/poi_label_layout_test.dart
flutter test test/route_label_layout_test.dart
```

The suite covers OSM parsing and caching, route topology, coastlines,
shorelines, object persistence across zoom levels, Bit/tree depth ordering,
label collision handling, and conservative POI metadata treatment.

## External data and services

| Service | Use | Notes |
| --- | --- | --- |
| OpenStreetMap | Map geometry and tags | Data © OpenStreetMap contributors, ODbL |
| Overpass | Viewport data and trail search | Public instances are subject to timeouts, rate limits, and outages |
| tile.openstreetmap.org | Offline-area selection only | Not used as the main pixel-art map background |
| Waymarked Trails | Hiking overlay in offline selection | External service, not included in the main graphic cache |
| Nostr relays | Voluntary track publishing | GPS tracks become public only after explicit confirmation |
| Hugging Face | Optional Kokoro model download | Files are checked for size and SHA-256 before use |

Overpass is not suitable for bulk regional downloads. The current cell cache
is a prototype solution; regional PBF extracts or open vector tiles are the
intended direction for larger areas and reliable offline use.

## Privacy and safety

- WildBit does not require an account for maps, GPS, or recording.
- On Android, location uses `LocationManager` with
  `forceLocationManager: true`; the Google Play Services fused provider is
  not requested.
- The database is encrypted with a random key held in the platform secure
  storage.
- Amber is the recommended Nostr method: the private key never enters the
  WildBit process.
- Direct nsec entry is supported, but stores the key in device secure storage
  and is therefore a more sensitive option.
- Nostr publishing includes the exact GPS points of a track. The UI must obtain
  explicit confirmation before sending.
- The voice model is optional and inference runs locally after download.

## Known limitations

- Public Overpass instances may return `429`, `500`, `502`, or time out;
  local caching and mirrors reduce but do not eliminate this problem.
- Global coastlines and complex islands need further validation against large,
  real-world datasets.
- Offline selection works, but the pipeline is not yet equivalent to a complete
  regional map package.
- Opening hours, access, drinkability, and difficulty are OSM observations, not
  guarantees of current real-world conditions.
- Battery life, memory use, and frame time still need measurement across a
  wider range of Android devices.
- Kokoro requires a relatively large initial download.

## Technical documentation

- [`docs/pixel_map_renderer_spec.md`](docs/pixel_map_renderer_spec.md) —
  renderer visual language and layer specification
- [`docs/pixel_map_mock_assets.md`](docs/pixel_map_mock_assets.md) — assets,
  anchors, footprints, and occlusion rules
- [`docs/coastline_composition.md`](docs/coastline_composition.md) —
  coastline, chain, and island rules
- [`docs/map_rendering_performance.md`](docs/map_rendering_performance.md) —
  budgets and performance principles
- [`roadmap.txt`](roadmap.txt) — historical renderer roadmap

Some documents also describe earlier goals and budgets. The code and tests are
the source of truth for currently implemented behaviour.

## License

WildBit is free software licensed under the
[GNU General Public License version 3](LICENSE), identified by the SPDX
expression `GPL-3.0-only`.

You may use, study, modify, and redistribute WildBit under the terms of that
license. If you distribute a modified version or a product containing covered
WildBit code, the corresponding source must remain available under GPLv3.

Files in `third_party/` retain their own copyright notices and licenses.
OpenStreetMap data is © OpenStreetMap contributors and is available under the
ODbL. Third-party trademarks, services, datasets, models, and names remain the
property of their respective owners.
