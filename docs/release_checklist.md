# WildBit release checklist

WildBit is distributed under **GNU GPLv3-only**. The repository already ships
the complete `LICENSE`; every release artifact must keep that license and the
source offer in the package metadata.

## Local preflight

From the repository root:

```bash
dart run tool/check_release.dart
```

The preflight checks the version, GPLv3 license, launcher icon densities and
PNG alpha channels, mascot/splash assets and Android `compileSdk = 37`. It reports the current
debug-signing fallback as a warning. CI or a distribution build must use:

```bash
dart run tool/check_release.dart --strict
```

`--strict` intentionally fails until a production keystore is configured.

## Android artifact

Before publishing an APK/AAB:

1. Configure a private release keystore through CI secrets (never commit the
   keystore or passwords) and export these variables:

   ```text
   WILDBIT_RELEASE_STORE_FILE
   WILDBIT_RELEASE_STORE_PASSWORD
   WILDBIT_RELEASE_KEY_ALIAS
   WILDBIT_RELEASE_KEY_PASSWORD
   ```

   The Gradle script uses the release signing config only when all four are
   present; otherwise it deliberately falls back to the debug key for local
   smoke tests.

   The manual GitHub Actions release additionally expects
   `WILDBIT_RELEASE_KEYSTORE_B64`, containing the base64-encoded keystore. The
   workflow writes it only to the ephemeral runner and uploads only the AAB.
2. Run `flutter build appbundle --release` and inspect the generated bundle
   with `apkanalyzer`/Play Console internal testing.
   For direct APK sideloads, use `flutter build apk --release
   --split-per-abi`: the local verification produced approximately 43.6 MB
   (armeabi-v7a), 51.2 MB (arm64-v8a), and 56.7 MB (x86_64), instead of
   shipping one universal APK containing every native ABI.
3. Verify that the drawer uses `assets/icons/icon.png` and the launch screen
   uses the transparent Bit artwork in `drawable-nodpi/bit_splash.png`.
4. Run the profile pan/zoom scenario from
   `docs/map_rendering_performance.md` on at least one mid-range Android
   device before signing the artifact.

The current debug signing fallback remains useful for local smoke tests only;
it is not a distributable release configuration.
