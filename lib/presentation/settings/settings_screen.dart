import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/theme_provider.dart';
import '../../app/theme/wildbit_theme.dart';
import '../../domain/entities/nostr_identity.dart';
import '../../services/kokoro/kokoro_model_manager.dart';
import '../../services/kokoro/kokoro_voices.dart';
import '../../services/kokoro/wildbit_voice_service.dart';
import '../../services/nostr/amber_signer_service.dart';
import '../../services/nostr/nostr_profile_service.dart';
import '../../services/security/backup_service.dart';
import '../../services/security/database_key_manager.dart';
import '../../app/localization/app_localizations.dart';

enum _KokoroStatus { unknown, notDownloaded, downloading, ready }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _KokoroStatus _kokoroStatus = _KokoroStatus.unknown;
  double _downloadProgress = 0;
  StreamSubscription<double>? _progressSub;
  StreamSubscription<String>? _errorSub;
  bool _previewing = false;

  NostrIdentity? _nostrIdentity;
  NostrProfile? _nostrProfile;
  bool _loadingNostrProfile = false;
  bool _linkingNostr = false;
  bool _exportingBackup = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedIdentity();
    _checkKokoroStatus();
    final manager = KokoroModelManager.instance;
    if (manager.isDownloading) {
      _kokoroStatus = _KokoroStatus.downloading;
      _downloadProgress = manager.lastProgress;
    }
    _progressSub = manager.progressStream.listen((p) {
      setState(() {
        _downloadProgress = p;
        if (p >= 1.0) _kokoroStatus = _KokoroStatus.ready;
      });
      if (p >= 1.0) _reinitVoice();
    });
    _errorSub = manager.errorStream.listen((_) {
      if (mounted) setState(() => _kokoroStatus = _KokoroStatus.notDownloaded);
    });
  }

  Future<void> _checkKokoroStatus() async {
    final ready = await KokoroModelManager.instance.isReady(
      kokoroSupportedLanguages,
    );
    if (!mounted) return;
    setState(
      () => _kokoroStatus = ready
          ? _KokoroStatus.ready
          : _KokoroStatus.notDownloaded,
    );
    if (ready) _reinitVoice();
  }

  void _reinitVoice() {
    // "Follow system" (locale == null) must fall back to the device's own
    // locale, not a hardcoded language — otherwise a user who never touched
    // this screen's language picker could have Bit's voice silently
    // reinitialize in Italian the moment this runs (e.g. right after the
    // Kokoro model finishes downloading).
    final code =
        context.read<WildBitLocaleProvider>().locale?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final supported = kokoroSupportedLanguages.contains(code) ? code : 'en';
    context.read<WildBitVoiceService>().init(supported);
  }

  void _setLocale(Locale? locale) {
    context.read<WildBitLocaleProvider>().setLocale(locale);
    _reinitVoice();
  }

  void _downloadKokoroModel() {
    setState(() => _kokoroStatus = _KokoroStatus.downloading);
    KokoroModelManager.instance.startDownload(kokoroSupportedLanguages);
  }

  Future<void> _previewVoice() async {
    final voice = context.read<WildBitVoiceService>();
    if (!voice.isReady || _previewing) return;
    setState(() => _previewing = true);
    await voice.speak(context.l10n.voicePreviewText);
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _loadLinkedIdentity() async {
    final identity = await context.read<DatabaseKeyManager>().linkedIdentity;
    if (!mounted) return;
    setState(() => _nostrIdentity = identity);
    if (identity != null) _loadNostrProfile(identity);
  }

  Future<void> _loadNostrProfile(NostrIdentity identity) async {
    if (mounted) setState(() => _loadingNostrProfile = true);
    final profile = await NostrProfileService.instance.fetch(
      identity.pubkeyHex,
    );
    if (!mounted || _nostrIdentity?.pubkeyHex != identity.pubkeyHex) return;
    setState(() {
      _nostrProfile = profile;
      _loadingNostrProfile = false;
    });
  }

  Future<void> _loginWithAmber() async {
    final signer = context.read<AmberSignerService>();
    final keyManager = context.read<DatabaseKeyManager>();
    if (!await signer.isInstalled()) {
      if (mounted) _showSnack(context.l10n.amberNotInstalled);
      return;
    }

    setState(() => _linkingNostr = true);
    try {
      final identity = await signer.login();
      if (identity == null) {
        if (mounted) _showSnack(context.l10n.amberCancelled);
        return;
      }
      final linked = await keyManager.linkNostrIdentity(identity, signer);
      if (!linked) {
        if (mounted) {
          _showSnack(context.l10n.amberEncryptionFailed);
        }
        return;
      }
      if (mounted) {
        setState(() {
          _nostrIdentity = identity;
          _nostrProfile = null;
        });
        _loadNostrProfile(identity);
      }
    } finally {
      if (mounted) setState(() => _linkingNostr = false);
    }
  }

  Future<void> _unlinkNostr() async {
    await context.read<DatabaseKeyManager>().unlinkNostrIdentity();
    if (mounted) {
      setState(() {
        _nostrIdentity = null;
        _nostrProfile = null;
      });
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _exportingBackup = true);
    try {
      await BackupService().exportAndShare();
    } catch (e) {
      if (mounted) _showSnack(context.l10n.exportFailed(e));
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<WildBitLocaleProvider>();
    final voice = context.watch<WildBitVoiceService>();
    final c = WildBitColorsExt.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(context.l10n.text('settings.appearance'), c),
          _ThemeSelector(themeProvider: themeProvider, c: c),
          _LanguageSelector(
            provider: localeProvider,
            onChanged: _setLocale,
            c: c,
          ),
          _SwitchTile(
            title: context.l10n.text('settings.autoDark'),
            subtitle: context.l10n.text('settings.autoDarkBody'),
            value: themeProvider.autoDarkEnabled,
            onChanged: themeProvider.setAutoDarkEnabled,
            c: c,
          ),
          const SizedBox(height: 24),
          _SectionHeader(context.l10n.text('settings.voice'), c),
          _KokoroCard(
            status: _kokoroStatus,
            progress: _downloadProgress,
            voice: voice,
            previewing: _previewing,
            onDownload: _downloadKokoroModel,
            onPreview: _previewVoice,
            onGenderChanged: (gender) {
              voice.setGender(gender);
              _reinitVoice();
            },
            onSpeedChanged: voice.setSpeed,
            onVolumeChanged: voice.setVolume,
            c: c,
          ),
          const SizedBox(height: 24),
          _SectionHeader(context.l10n.text('settings.security'), c),
          _NostrIdentityCard(
            identity: _nostrIdentity,
            profile: _nostrProfile,
            profileLoading: _loadingNostrProfile,
            linking: _linkingNostr,
            onLogin: _loginWithAmber,
            onLogout: _unlinkNostr,
            c: c,
          ),
          const SizedBox(height: 8),
          _BackupTile(
            hasIdentity: _nostrIdentity != null,
            exporting: _exportingBackup,
            onExport: _exportBackup,
            c: c,
          ),
          const SizedBox(height: 24),
          _SectionHeader(context.l10n.text('settings.support'), c),
          const _DonationTile(),
          const SizedBox(height: 24),
          _SectionHeader(context.l10n.text('settings.info'), c),
          _InfoTile(c: c),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.themeProvider, required this.c});

  final ThemeProvider themeProvider;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(child: Text(context.l10n.text('settings.theme'))),
          SegmentedButton<AppThemeId>(
            segments: [
              ButtonSegment(
                value: AppThemeId.light,
                label: Text(context.l10n.text('settings.light')),
                icon: const Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: AppThemeId.dark,
                label: Text(context.l10n.text('settings.dark')),
                icon: const Icon(Icons.dark_mode),
              ),
            ],
            selected: {themeProvider.current},
            onSelectionChanged: (selection) =>
                themeProvider.setTheme(selection.first),
          ),
        ],
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.provider,
    required this.onChanged,
    required this.c,
  });

  final WildBitLocaleProvider provider;
  final ValueChanged<Locale?> onChanged;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    final selected = provider.locale?.languageCode;
    final selectedName = selected == null
        ? context.l10n.text('settings.system')
        : (wildBitLanguageNames[selected] ?? selected);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Material(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.language, color: c.accent),
          title: Text(context.l10n.text('settings.language')),
          subtitle: Text(selectedName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(
                      selected == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(context.l10n.text('settings.system')),
                    onTap: () {
                      onChanged(null);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  for (final locale in wildBitLocales)
                    ListTile(
                      leading: Icon(
                        selected == locale.languageCode
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(
                        wildBitLanguageNames[locale.languageCode] ??
                            locale.languageCode,
                      ),
                      onTap: () {
                        onChanged(locale);
                        Navigator.pop(sheetContext);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KokoroCard extends StatelessWidget {
  const _KokoroCard({
    required this.status,
    required this.progress,
    required this.voice,
    required this.previewing,
    required this.onDownload,
    required this.onPreview,
    required this.onGenderChanged,
    required this.onSpeedChanged,
    required this.onVolumeChanged,
    required this.c,
  });

  final _KokoroStatus status;
  final double progress;
  final WildBitVoiceService voice;
  final bool previewing;
  final VoidCallback onDownload;
  final VoidCallback onPreview;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onVolumeChanged;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    final localeCode =
        context.watch<WildBitLocaleProvider>().locale?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final voiceUnavailableInLanguage = !kokoroSupportedLanguages.contains(
      localeCode,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.text('settings.voiceModel'),
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(switch (status) {
            _KokoroStatus.ready => context.l10n.text('settings.voiceReady'),
            _KokoroStatus.downloading => context.l10n.text(
              'settings.voiceDownloading',
            ),
            _ => context.l10n.text('settings.voiceMissing'),
          }, style: TextStyle(color: c.textSecondary, fontSize: 12)),
          if (voiceUnavailableInLanguage) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: c.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.voiceUnavailableInLanguage,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (status == _KokoroStatus.downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
          ],
          if (status == _KokoroStatus.notDownloaded) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: Text(context.l10n.text('settings.downloadVoice')),
            ),
          ],
          if (status == _KokoroStatus.ready) ...[
            const SizedBox(height: 12),
            Text(context.l10n.text('settings.voiceChoice')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(context.l10n.text('settings.female')),
                  selected: voice.gender == 'f',
                  onSelected: (_) => onGenderChanged('f'),
                ),
                if (kokoroHasGenderChoice(voice.language))
                  ChoiceChip(
                    label: Text(context.l10n.text('settings.male')),
                    selected: voice.gender == 'm',
                    onSelected: (_) => onGenderChanged('m'),
                  ),
                ChoiceChip(
                  label: Text(context.l10n.text('settings.bitVoice')),
                  selected: voice.gender == 'bit',
                  onSelected: (_) => onGenderChanged('bit'),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(context.l10n.text('settings.speed')),
                ),
                Expanded(
                  child: Slider(
                    value: voice.speed,
                    min: 0.7,
                    max: 1.5,
                    divisions: 8,
                    label: '${context.l10n.decimal(voice.speed, digits: 2)}×',
                    onChanged: onSpeedChanged,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(context.l10n.text('settings.volume')),
                ),
                Expanded(
                  child: Slider(
                    value: voice.volume,
                    onChanged: onVolumeChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: previewing ? null : onPreview,
              icon: Icon(previewing ? Icons.hourglass_top : Icons.play_arrow),
              label: Text(
                previewing
                    ? context.l10n.text('settings.playing')
                    : context.l10n.text('settings.tryVoice'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.c,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: SwitchListTile(
          title: Text(title),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _NostrIdentityCard extends StatelessWidget {
  const _NostrIdentityCard({
    required this.identity,
    required this.profile,
    required this.profileLoading,
    required this.linking,
    required this.onLogin,
    required this.onLogout,
    required this.c,
  });

  final NostrIdentity? identity;
  final NostrProfile? profile;
  final bool profileLoading;
  final bool linking;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    final identity = this.identity;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.text('settings.nostr'),
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (identity == null)
            Text(
              context.l10n.nostrSecurityBody,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _NostrAvatar(profile: profile, color: c.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.preferredName ??
                            (profileLoading
                                ? context.l10n.text('settings.profileLoading')
                                : context.l10n.text('settings.profile')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.connectedAs(identity.npub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (identity == null)
            FilledButton.icon(
              onPressed: linking ? null : onLogin,
              icon: Icon(linking ? Icons.hourglass_top : Icons.login),
              label: Text(
                linking
                    ? context.l10n.text('common.waitingAmber')
                    : context.l10n.text('onboarding.loginAmber'),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: Text(context.l10n.text('settings.unlink')),
            ),
        ],
      ),
    );
  }
}

class _NostrAvatar extends StatelessWidget {
  const _NostrAvatar({required this.profile, required this.color});

  final NostrProfile? profile;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uri = profile?.pictureUri;
    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.14),
      child: uri == null
          ? Icon(Icons.person_outline, color: color)
          : ClipOval(
              child: Image.network(
                uri.toString(),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.person_outline, color: color),
              ),
            ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.hasIdentity,
    required this.exporting,
    required this.onExport,
    required this.c,
  });

  final bool hasIdentity;
  final bool exporting;
  final VoidCallback onExport;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.backup, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.text('settings.backup'),
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.backupBody(hasIdentity),
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: exporting ? null : onExport,
            icon: Icon(exporting ? Icons.hourglass_top : Icons.ios_share),
            label: Text(
              exporting
                  ? context.l10n.text('settings.exporting')
                  : context.l10n.text('settings.exportBackup'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationTile extends StatelessWidget {
  const _DonationTile();

  static const _lnAddress = 'lwb89@blink.sv';

  @override
  Widget build(BuildContext context) {
    final c = WildBitColorsExt.of(context);
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse('lightning:$_lnAddress');
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
        if (launched) return;
        await Clipboard.setData(const ClipboardData(text: _lnAddress));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.copiedAddress(_lnAddress))),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: c.accent.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, color: c.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('settings.donation'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lnAddress,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 14, color: c.accent),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.c});

  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WildBit', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            context.l10n.aboutTagline,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.aboutCredits,
            style: TextStyle(color: c.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.c);

  final String title;
  final WildBitColorsExt c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
