import 'dart:io';

/// Lightweight, dependency-free release preflight.
///
/// Run from the repository root with `dart run tool/check_release.dart`.
/// Add `--strict` in CI to reject the development signing fallback.
void main(List<String> arguments) {
  final strict = arguments.contains('--strict');
  final failures = <String>[];
  final warnings = <String>[];

  void requireFile(String path) {
    if (!File(path).existsSync()) failures.add('missing file: $path');
  }

  void requirePng(String path, {int? width, int? height}) {
    requireFile(path);
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    final validSignature =
        bytes.length >= 26 &&
        List<int>.generate(8, (index) => bytes[index]).join(',') ==
            signature.join(',');
    if (!validSignature) {
      failures.add('$path is not a valid PNG');
      return;
    }
    int readUint32(int offset) =>
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    final actualWidth = readUint32(16);
    final actualHeight = readUint32(20);
    // PNG colour type 4/6 contains an alpha channel. Launcher art must stay
    // transparent so Android does not add a black square around the icon.
    final colourType = bytes[25];
    if (colourType != 4 && colourType != 6) {
      failures.add('$path has no alpha channel');
    }
    if (width != null && actualWidth != width ||
        height != null && actualHeight != height) {
      failures.add(
        '$path has unexpected dimensions ${actualWidth}x$actualHeight',
      );
    }
  }

  requireFile('LICENSE');
  requireFile('README.md');
  requirePng('assets/icons/icon.png');
  requirePng('assets/icons/mascotte.png');
  requirePng(
    'android/app/src/main/res/drawable-nodpi/bit_splash.png',
    width: 1230,
    height: 1278,
  );
  const launcherSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in launcherSizes.entries) {
    requirePng(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      width: entry.value,
      height: entry.value,
    );
  }

  final license = File('LICENSE').existsSync()
      ? File('LICENSE').readAsStringSync()
      : '';
  if (!license.contains('GNU GENERAL PUBLIC LICENSE') ||
      !license.contains('Version 3')) {
    failures.add('LICENSE is not recognisable as GPLv3');
  }

  final pubspec = File('pubspec.yaml').existsSync()
      ? File('pubspec.yaml').readAsStringSync()
      : '';
  final version = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (version == null || version == '0.0.0+0') {
    failures.add('pubspec.yaml has no release version');
  } else {
    stdout.writeln('version: $version');
  }

  final gradle = File('android/app/build.gradle.kts').existsSync()
      ? File('android/app/build.gradle.kts').readAsStringSync()
      : '';
  final compileSdk = RegExp(
    r'compileSdk\s*=\s*(\d+)',
  ).firstMatch(gradle)?.group(1);
  if (compileSdk == null || int.parse(compileSdk) < 37) {
    failures.add('Android compileSdk must remain 37 or newer');
  }
  final signingVariables = [
    'WILDBIT_RELEASE_STORE_FILE',
    'WILDBIT_RELEASE_STORE_PASSWORD',
    'WILDBIT_RELEASE_KEY_ALIAS',
    'WILDBIT_RELEASE_KEY_PASSWORD',
  ];
  final signingConfigured = signingVariables.every(
    (name) => (Platform.environment[name] ?? '').trim().isNotEmpty,
  );
  if (!signingConfigured) {
    warnings.add('release still uses the debug signing key');
    if (strict) failures.add('production signing is not configured');
  }

  for (final warning in warnings) {
    stderr.writeln('warning: $warning');
  }
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('error: $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('release preflight: OK');
}
