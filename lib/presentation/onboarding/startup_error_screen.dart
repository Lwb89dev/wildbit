import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../app/localization/app_localizations.dart';

/// Shown, before the encrypted database is opened, when the platform secure
/// storage cannot provide the database key. Nothing is reset or deleted: a
/// new key would make the existing database unreadable, so the only action
/// is to try again (a Keystore hiccup right after boot usually clears).
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  WildBitLocalizations get _l10n {
    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final locale =
        const WildBitLocalizationsDelegate().isSupported(platformLocale)
        ? Locale(platformLocale.languageCode)
        : const Locale('en');
    return WildBitLocalizations(locale);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: WildBitLocalizations.supportedLocales,
      localizationsDelegates: const [
        WildBitLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_clock_outlined, size: 48),
                const SizedBox(height: 20),
                Text(
                  l10n.text('startup.storageErrorTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(l10n.text('startup.storageErrorBody')),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.text('common.retry')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
