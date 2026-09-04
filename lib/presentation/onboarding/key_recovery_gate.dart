import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../services/nostr/amber_signer_service.dart';
import '../../services/security/database_key_manager.dart';
import '../../app/localization/app_localizations.dart';

/// Shown, before the encrypted database is ever opened, only when
/// [DatabaseKeyManager.hasRecoverableIdentity] says this install has Nostr
/// link metadata but no local key yet — i.e. a reinstall or a restore onto a
/// new device. Recovering here means the restored `.sqlite` backup opens
/// with its original key instead of [DatabaseKeyManager.resolveKey] silently
/// generating a new, unrelated one.
class KeyRecoveryGate extends StatefulWidget {
  const KeyRecoveryGate({
    super.key,
    required this.keyManager,
    required this.onKeyResolved,
  });

  final DatabaseKeyManager keyManager;
  final ValueChanged<String> onKeyResolved;

  @override
  State<KeyRecoveryGate> createState() => _KeyRecoveryGateState();
}

class _KeyRecoveryGateState extends State<KeyRecoveryGate> {
  final _signer = AmberSignerService();
  bool _recovering = false;
  String? _error;

  WildBitLocalizations get _l10n {
    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final locale = WildBitLocalizationsDelegate().isSupported(platformLocale)
        ? Locale(platformLocale.languageCode)
        : const Locale('en');
    return WildBitLocalizations(locale);
  }

  Future<void> _recover() async {
    setState(() {
      _recovering = true;
      _error = null;
    });
    try {
      if (!await _signer.isInstalled()) {
        setState(() => _error = _l10n.amberNotInstalled);
        return;
      }
      final key = await widget.keyManager.recoverKeyFromAmber(_signer);
      if (key == null) {
        setState(() => _error = _l10n.amberCancelled);
        return;
      }
      widget.onKeyResolved(key);
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Future<void> _startFresh() async {
    widget.onKeyResolved(await widget.keyManager.resolveKey());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    return MaterialApp(
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
                const Icon(Icons.lock_reset_rounded, size: 48),
                const SizedBox(height: 20),
                Text(
                  l10n.text('onboarding.restoreDatabase'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(l10n.text('onboarding.restoreBody')),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _recovering ? null : _recover,
                    icon: _recovering
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.key),
                    label: Text(
                      _recovering
                          ? l10n.text('common.recovering')
                          : l10n.text('common.recoverAmber'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _recovering ? null : _startFresh,
                  child: Text(l10n.text('onboarding.startFresh')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
