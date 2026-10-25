import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../location/geolocator_location_service.dart';
import '../location/location_service.dart';
import '../presentation/onboarding/onboarding_screen.dart';
import '../presentation/shared/root_shell.dart';
import 'theme/theme_provider.dart';
import 'localization/app_localizations.dart';

class WildBitApp extends StatefulWidget {
  const WildBitApp({super.key, required this.locationService});

  final LocationService locationService;

  @override
  State<WildBitApp> createState() => _WildBitAppState();
}

class _WildBitAppState extends State<WildBitApp> {
  static const _onboardingKey = 'wildbit.onboarding.v1';
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _onboardingComplete = prefs.getBool(_onboardingKey) ?? false,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<WildBitLocaleProvider>();
    return MaterialApp(
      title: 'WildBit',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.effectiveThemeData,
      locale: localeProvider.locale,
      supportedLocales: WildBitLocalizations.supportedLocales,
      localizationsDelegates: const [
        WildBitLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) {
        // The location plugin posts the foreground-service notification
        // outside the widget tree; give it the active language's text.
        GeolocatorLocationService.foregroundNotificationText = context.l10n
            .text('location.foregroundNotification');
        return child ?? const SizedBox.shrink();
      },
      home: switch (_onboardingComplete) {
        null => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        true => RootShell(locationService: widget.locationService),
        false => OnboardingScreen(
          locationService: widget.locationService,
          onComplete: _completeOnboarding,
        ),
      },
    );
  }
}
