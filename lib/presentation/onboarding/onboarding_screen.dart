import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nostr_tools/nostr_tools.dart';
import 'package:provider/provider.dart';

import '../../app/theme/wildbit_theme.dart';
import '../../location/location_service.dart';
import '../../domain/entities/nostr_identity.dart';
import '../../services/nostr/amber_signer_service.dart';
import '../../services/security/database_key_manager.dart';
import '../../app/localization/app_localizations.dart';

/// First-launch guide for the on-device hiking experience. It explicitly
/// explains why location is useful before WildBit ever asks Android for it.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.locationService,
    required this.onComplete,
  });

  final LocationService locationService;
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _locationGranted = false;
  bool _requestingLocation = false;
  bool _locationDenied = false;
  NostrIdentity? _nostrIdentity;
  bool _waitingAmber = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 3) {
      widget.onComplete();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loginWithAmber() async {
    setState(() => _waitingAmber = true);
    try {
      final signer = context.read<AmberSignerService>();
      final databaseKeys = context.read<DatabaseKeyManager>();
      final identity = await signer.login();
      if (identity == null) return;
      if (await databaseKeys.linkNostrIdentity(identity, signer)) {
        if (mounted) setState(() => _nostrIdentity = identity);
      }
    } finally {
      if (mounted) setState(() => _waitingAmber = false);
    }
  }

  Future<void> _loginWithNsec(String nsec) async {
    try {
      final decoded = Nip19().decode(nsec);
      if (decoded['type'] != 'nsec') throw const FormatException();
      final privateKey = decoded['data'] as String;
      final pubkey = KeyApi().getPublicKey(privateKey);
      final identity = NostrIdentity(
        pubkeyHex: pubkey,
        npub: Nip19().npubEncode(pubkey),
      );
      await context.read<DatabaseKeyManager>().linkNsecIdentity(identity, nsec);
      if (mounted) setState(() => _nostrIdentity = identity);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.invalidNsec)));
    }
  }

  Future<void> _requestLocation() async {
    setState(() {
      _requestingLocation = true;
      _locationDenied = false;
    });
    final granted = await widget.locationService.ensurePermission();
    if (!mounted) return;
    setState(() {
      _requestingLocation = false;
      _locationGranted = granted;
      _locationDenied = !granted;
    });
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    return Scaffold(
      backgroundColor: colors.surface1,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: _ProgressDots(page: _page, color: colors.accent),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _WelcomePage(onNext: _next),
                  _NostrPage(
                    identity: _nostrIdentity,
                    waiting: _waitingAmber,
                    onAmber: _loginWithAmber,
                    onNsec: _loginWithNsec,
                    onNext: _next,
                  ),
                  _LocationPage(
                    granted: _locationGranted,
                    requesting: _requestingLocation,
                    denied: _locationDenied,
                    onRequest: _requestLocation,
                    onSettings: _openLocationSettings,
                    onNext: _next,
                  ),
                  _ReadyPage(onStart: _next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.page, required this.color});

  final int page;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(
      4,
      (index) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: page == index ? 22 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: page == index ? color : color.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    ),
  );
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(28, 18, 28, 26), child: child);

  Widget iconCard(BuildContext context, IconData icon) {
    final colors = WildBitColorsExt.of(context);
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: colors.accent, size: 29),
    );
  }

  Widget primaryButton(
    BuildContext context,
    String label,
    VoidCallback onPressed,
  ) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15),
      ),
      child: Text(label),
    ),
  );
}

class _WelcomePage extends _OnboardingPage {
  const _WelcomePage({required this.onNext}) : super(child: const SizedBox());

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    final features = [
      (Icons.terrain_rounded, context.l10n.text('onboarding.featureMaps')),
      (Icons.hiking_rounded, context.l10n.text('onboarding.featureTracks')),
      (Icons.explore_outlined, context.l10n.text('onboarding.featureExplore')),
    ];
    return _OnboardingPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Image.asset(
              'assets/icons/mascotte.png',
              height: 132,
              fit: BoxFit.contain,
            ),
          ),
          Text(
            'WildBit',
            style: TextStyle(
              color: colors.accent,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('onboarding.welcomeTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('onboarding.welcomeBody'),
            style: TextStyle(color: colors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: features.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final feature = features[index];
                return _FeatureRow(icon: feature.$1, text: feature.$2);
              },
            ),
          ),
          primaryButton(context, context.l10n.text('onboarding.start'), onNext),
        ],
      ),
    );
  }
}

class _NostrPage extends _OnboardingPage {
  const _NostrPage({
    required this.identity,
    required this.waiting,
    required this.onAmber,
    required this.onNsec,
    required this.onNext,
  }) : super(child: const SizedBox());

  final NostrIdentity? identity;
  final bool waiting;
  final Future<void> Function() onAmber;
  final Future<void> Function(String nsec) onNsec;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    final connected = identity != null;
    return _OnboardingPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconCard(context, Icons.key_rounded),
          const SizedBox(height: 22),
          Text(
            context.l10n.text('onboarding.nostrTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('onboarding.nostrBody'),
            style: TextStyle(color: colors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (connected)
            ListTile(
              leading: const Icon(
                Icons.verified_user,
                color: WildBitColors.forestGreen,
              ),
              title: Text(context.l10n.text('onboarding.connected')),
              subtitle: Text(
                identity!.npub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else ...[
            primaryButton(
              context,
              waiting
                  ? context.l10n.text('onboarding.waitingAmber')
                  : context.l10n.text('onboarding.loginAmber'),
              waiting
                  ? () {}
                  : () {
                      onAmber();
                    },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _askNsec(context),
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(context.l10n.text('onboarding.enterNsec')),
            ),
          ],
          const Spacer(),
          Text(
            context.l10n.text('onboarding.later'),
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          primaryButton(
            context,
            connected
                ? context.l10n.text('common.continue')
                : context.l10n.text('onboarding.skip'),
            onNext,
          ),
        ],
      ),
    );
  }

  void _askNsec(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('onboarding.enterNsec')),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'nsec1…',
            helperText: context.l10n.text('onboarding.nsecHelper'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onNsec(controller.text.trim());
            },
            child: Text(context.l10n.text('common.continue')),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _LocationPage extends _OnboardingPage {
  const _LocationPage({
    required this.granted,
    required this.requesting,
    required this.denied,
    required this.onRequest,
    required this.onSettings,
    required this.onNext,
  }) : super(child: const SizedBox());

  final bool granted;
  final bool requesting;
  final bool denied;
  final VoidCallback onRequest;
  final VoidCallback onSettings;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    return _OnboardingPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconCard(context, Icons.location_on_rounded),
          const SizedBox(height: 22),
          Text(
            context.l10n.text('onboarding.locationTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('onboarding.locationBody'),
            style: TextStyle(color: colors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          _PermissionCard(granted: granted, denied: denied),
          const Spacer(),
          if (requesting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!granted)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(context.l10n.text('onboarding.allowLocation')),
              ),
            ),
          if (denied) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(context.l10n.text('onboarding.openSettings')),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onNext,
            child: Text(
              granted
                  ? context.l10n.text('common.continue')
                  : context.l10n.text('onboarding.continueWithoutLocation'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyPage extends _OnboardingPage {
  const _ReadyPage({required this.onStart}) : super(child: const SizedBox());

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    return _OnboardingPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconCard(context, Icons.explore_rounded),
          const SizedBox(height: 22),
          Text(
            context.l10n.text('onboarding.readyTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.text('onboarding.readyBody'),
            style: TextStyle(color: colors.textSecondary, height: 1.5),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: colors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.text('onboarding.localTracks'),
                    style: TextStyle(color: colors.textPrimary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          primaryButton(
            context,
            context.l10n.text('onboarding.openWildBit'),
            onStart,
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: colors.textPrimary, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.granted, required this.denied});

  final bool granted;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final colors = WildBitColorsExt.of(context);
    final color = granted
        ? Colors.green.shade700
        : (denied ? Colors.orange.shade800 : colors.accent);
    final label = granted
        ? context.l10n.text('location.allowed')
        : denied
        ? context.l10n.text('location.denied')
        : context.l10n.text('location.required');
    final icon = granted
        ? Icons.check_circle_rounded
        : Icons.location_searching_rounded;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
