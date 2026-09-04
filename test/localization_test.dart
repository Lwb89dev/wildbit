import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/app/localization/app_localizations.dart';

void main() {
  test('ships every requested locale and localises core navigation', () {
    expect(wildBitLocales.length, 27);
    expect(
      wildBitLocales.map((locale) => locale.languageCode).toSet().length,
      27,
    );

    for (final locale in wildBitLocales) {
      final l10n = WildBitLocalizations(locale);
      expect(wildBitLanguageNames[locale.languageCode], isNotNull);
      expect(l10n.text('nav.map'), isNot('nav.map'));
      expect(l10n.text('nav.settings'), isNot('nav.settings'));
    }
  });

  test('uses regional decimal separators', () {
    expect(WildBitLocalizations(const Locale('it')).decimal(12.5), '12,5');
    expect(WildBitLocalizations(const Locale('de')).decimal(12.5), '12,5');
    expect(WildBitLocalizations(const Locale('en')).decimal(12.5), '12.5');
    expect(WildBitLocalizations(const Locale('zh')).decimal(12.5), '12.5');
  });

  test('uses English as the fallback for unsupported system languages', () {
    expect(WildBitLocalizations.supportedLocales.first, const Locale('en'));
    expect(
      WildBitLocalizationsDelegate().isSupported(const Locale('xx')),
      isFalse,
    );
    expect(
      WildBitLocalizations(const Locale('xx')).text('nav.settings'),
      'Settings',
    );
    expect(
      WildBitLocalizations(
        const Locale('it'),
      ).param('map.routeDownloadFailed', {'failed': '2', 'count': '10'}),
      '2 celle non scaricate su 10 — riprova',
    );
  });
}
