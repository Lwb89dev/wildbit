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
import '../../services/security/backup_service.dart';
import '../../services/security/database_key_manager.dart';

enum _KokoroStatus { unknown, notDownloaded, downloading, ready }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _voiceLanguage = 'it';

  _KokoroStatus _kokoroStatus = _KokoroStatus.unknown;
  double _downloadProgress = 0;
  StreamSubscription<double>? _progressSub;
  StreamSubscription<String>? _errorSub;
  bool _previewing = false;

  NostrIdentity? _nostrIdentity;
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
    context.read<WildBitVoiceService>().init(_voiceLanguage);
  }

  void _downloadKokoroModel() {
    setState(() => _kokoroStatus = _KokoroStatus.downloading);
    KokoroModelManager.instance.startDownload(kokoroSupportedLanguages);
  }

  Future<void> _previewVoice() async {
    final voice = context.read<WildBitVoiceService>();
    if (!voice.isReady || _previewing) return;
    setState(() => _previewing = true);
    await voice.speak('Ciao! Sono Bit, la tua guida escursionistica.');
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _loadLinkedIdentity() async {
    final identity = await context.read<DatabaseKeyManager>().linkedIdentity;
    if (mounted) setState(() => _nostrIdentity = identity);
  }

  Future<void> _loginWithAmber() async {
    final signer = context.read<AmberSignerService>();
    final keyManager = context.read<DatabaseKeyManager>();
    if (!await signer.isInstalled()) {
      if (mounted) _showSnack('Amber non è installato su questo dispositivo.');
      return;
    }

    setState(() => _linkingNostr = true);
    try {
      final identity = await signer.login();
      if (identity == null) {
        if (mounted) _showSnack('Accesso con Amber annullato o non riuscito.');
        return;
      }
      final linked = await keyManager.linkNostrIdentity(identity, signer);
      if (!linked) {
        if (mounted)
          _showSnack('Amber non ha potuto cifrare la chiave del database.');
        return;
      }
      if (mounted) setState(() => _nostrIdentity = identity);
    } finally {
      if (mounted) setState(() => _linkingNostr = false);
    }
  }

  Future<void> _unlinkNostr() async {
    await context.read<DatabaseKeyManager>().unlinkNostrIdentity();
    if (mounted) setState(() => _nostrIdentity = null);
  }

  Future<void> _exportBackup() async {
    setState(() => _exportingBackup = true);
    try {
      await BackupService().exportAndShare();
    } catch (e) {
      if (mounted) _showSnack('Esportazione non riuscita: $e');
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
    final voice = context.watch<WildBitVoiceService>();
    final c = WildBitColorsExt.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Aspetto', c),
          _ThemeSelector(themeProvider: themeProvider, c: c),
          _SwitchTile(
            title: 'Tema scuro automatico',
            subtitle:
                'Passa al tema scuro tra tramonto e alba, in base alla posizione',
            value: themeProvider.autoDarkEnabled,
            onChanged: themeProvider.setAutoDarkEnabled,
            c: c,
          ),
          const SizedBox(height: 24),
          _SectionHeader('Voce di Bit', c),
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
          _SectionHeader('Sicurezza e backup', c),
          _NostrIdentityCard(
            identity: _nostrIdentity,
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
          _SectionHeader('Sostieni WildBit', c),
          const _DonationTile(),
          const SizedBox(height: 24),
          _SectionHeader('Informazioni', c),
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
          const Expanded(child: Text('Tema')),
          SegmentedButton<AppThemeId>(
            segments: const [
              ButtonSegment(
                value: AppThemeId.light,
                label: Text('Chiaro'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: AppThemeId.dark,
                label: Text('Scuro'),
                icon: Icon(Icons.dark_mode),
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
              const Expanded(
                child: Text(
                  'Modello vocale offline (Kokoro)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(switch (status) {
            _KokoroStatus.ready => 'Pronto — Bit può parlare offline',
            _KokoroStatus.downloading => 'Download in corso…',
            _ => 'Non scaricato (~87 MB, richiesto una sola volta)',
          }, style: TextStyle(color: c.textSecondary, fontSize: 12)),
          if (status == _KokoroStatus.downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
          ],
          if (status == _KokoroStatus.notDownloaded) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: const Text('Scarica il modello vocale'),
            ),
          ],
          if (status == _KokoroStatus.ready) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Voce'),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Femminile'),
                  selected: voice.gender == 'f',
                  onSelected: (_) => onGenderChanged('f'),
                ),
                const SizedBox(width: 6),
                if (kokoroHasGenderChoice('it'))
                  ChoiceChip(
                    label: const Text('Maschile'),
                    selected: voice.gender == 'm',
                    onSelected: (_) => onGenderChanged('m'),
                  ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Bit · kawaii'),
                  selected: voice.gender == 'bit',
                  onSelected: (_) => onGenderChanged('bit'),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 40, child: Text('Velocità')),
                Expanded(
                  child: Slider(
                    value: voice.speed,
                    min: 0.7,
                    max: 1.5,
                    divisions: 8,
                    label: '${voice.speed.toStringAsFixed(2)}×',
                    onChanged: onSpeedChanged,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 40, child: Text('Volume')),
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
              label: Text(previewing ? 'In riproduzione…' : 'Prova la voce'),
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
    required this.linking,
    required this.onLogin,
    required this.onLogout,
    required this.c,
  });

  final NostrIdentity? identity;
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
              const Expanded(
                child: Text(
                  'Identità Nostr',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            identity == null
                ? 'Il database è già cifrato localmente. Collega la tua identità Nostr con Amber per rendere la chiave recuperabile dal tuo nsec (utile per i backup).'
                : 'Collegato come ${identity.npub.substring(0, 12)}…',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (identity == null)
            FilledButton.icon(
              onPressed: linking ? null : onLogin,
              icon: Icon(linking ? Icons.hourglass_top : Icons.login),
              label: Text(linking ? 'In attesa di Amber…' : 'Accedi con Amber'),
            )
          else
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Scollega identità'),
            ),
        ],
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
              const Expanded(
                child: Text(
                  'Backup',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasIdentity
                ? 'Il file esportato è cifrato: recuperabile su un altro dispositivo tramite Amber e la tua identità Nostr.'
                : 'Il file esportato è cifrato con una chiave locale a questo dispositivo — senza un\'identità Nostr collegata non è recuperabile altrove.',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: exporting ? null : onExport,
            icon: Icon(exporting ? Icons.hourglass_top : Icons.ios_share),
            label: Text(exporting ? 'Esportazione…' : 'Esporta backup'),
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
            SnackBar(content: Text('Indirizzo copiato: $_lnAddress')),
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
                  const Text(
                    'Sostieni lo sviluppo di WildBit',
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
            'Real world, pixel world. Escursionismo offline-first con cartografia OpenStreetMap.',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            'Dati mappa © OpenStreetMap contributors · Voce: Kokoro-82M (onnx-community) · eSpeak NG',
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
