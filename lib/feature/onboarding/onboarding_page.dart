import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/pairing_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/feature/pairing/pairing_page.dart';
import 'package:aetherStream/feature/settings/backup_restore_flow.dart';

/// Onboarding 3 écrans affichés une seule fois (§1i + §3c-8 TV).
///
/// Stocke `onboarding_done_v1=true` dans SharedPreferences une fois fini.
/// L'aiguilleur (`_LaunchDecider` dans main.dart) consulte
/// [OnboardingService.shouldShow] avant la première navigation.
///
/// Sur **TV** (§3c-8) :
///   - Slide 1 : Welcome (inchangé)
///   - Slide 2 : `PairingPage` embarqué (kind=account) — l'utilisateur scanne
///     le QR avec son téléphone et remplit l'URL/login/pass dans une UI mobile
///     plutôt qu'au D-pad (saisie texte ~impossible sur télécommande).
///   - Slide 3 : `PairingPage` embarqué (kind=tmdb) — pareil pour le Bearer
///     Token TMDB (220 caractères, donc encore plus critique).
class OnboardingService {
  static const String _prefsKey = 'onboarding_done_v1';

  /// `true` si l'onboarding n'a jamais été complété.
  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_prefsKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  /// À appeler quand l'utilisateur termine l'onboarding.
  static Future<void> markDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {}
  }

  /// Debug : reset l'onboarding.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}

class OnboardingPage extends StatefulWidget {
  /// Callback appelé quand l'utilisateur termine ("Commencer") ou skip.
  /// Le parent décide ensuite où naviguer.
  final VoidCallback onFinish;
  const OnboardingPage({super.key, required this.onFinish});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _index = 0;

  bool get _isTv => PlatformTv.isTv;
  int get _slideCount => 3;

  Future<void> _finish() async {
    await OnboardingService.markDone();
    if (!mounted) return;
    widget.onFinish();
  }

  /// §restore — Récupération directe d'une sauvegarde `.aether` au 1er
  /// lancement (cas fréquent : réinstallation après uninstall, le fichier
  /// survit dans Download/AetherStream/). Si la restauration réussit, on
  /// termine l'onboarding et le parent recharge la config restaurée.
  Future<void> _onRestoreTap() async {
    final restored = await runBackupImportFlow(context);
    if (restored && mounted) {
      await _finish();
    }
  }

  void _next() {
    if (_index >= _slideCount - 1) {
      _finish();
      return;
    }
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  // Callbacks invoqués par les slides pairing TV après réception du résultat.
  Future<void> _onAccountReceived(PairingAccountResult r) async {
    await StreamAccountService.saveAccount(r.account);
    await StreamAccountService.setCurrentAccount(r.account.id);
    // §3c-8b — TMDB optionnel saisi dans le même form mobile : on l'applique
    // et on saute le slide 3 (pas besoin d'un second pairing).
    final t = r.tmdbToken;
    if (t != null && t.isNotEmpty) {
      await TmdbApiService.saveApiKey(t);
      TmdbService.resetInstance();
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 700), _finish);
      return;
    }
    if (!mounted) return;
    // Auto-advance vers slide TMDB après une courte pause.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _next();
    });
  }

  Future<void> _onTmdbReceived(PairingTmdbResult r) async {
    await TmdbApiService.saveApiKey(r.token);
    TmdbService.resetInstance();
    // Fin directe : TMDB est le dernier slide.
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 700), _finish);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _index == _slideCount - 1;
    // Sur TV, on masque "Suivant" sur les slides pairing (auto-advance après réception).
    final hideNext = _isTv && (_index == 1 || _index == 2);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.2),
                  radius: 1.4,
                  colors: [kAccentPrimary.withAlpha(35), cs.surface],
                )
              : null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Passer',
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: _slideCount,
                  // Sur TV en mode pairing, on désactive le swipe horizontal :
                  // PairingPage embed gère son propre scroll vertical et un
                  // swipe accidentel ferait perdre la session de pairing.
                  physics: _isTv && (_index == 1 || _index == 2)
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _buildSlide(i),
                ),
              ),
              // Dots indicator
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slideCount, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            active ? kAccentPrimary : cs.outline.withAlpha(80),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
              if (!hideNext)
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, _index == 0 ? 8 : 28),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentPrimary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      child: Text(isLast ? 'Commencer' : 'Suivant'),
                    ),
                  ),
                )
              else
                const SizedBox(height: 16),
              // §restore — Slide d'accueil uniquement : récupérer une sauvegarde.
              if (_index == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: TextButton.icon(
                    onPressed: _onRestoreTap,
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('J\'ai déjà une sauvegarde (.aether)'),
                    style: TextButton.styleFrom(
                      foregroundColor: kAccentSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(int i) {
    if (i == 0) return const _WelcomeSlide();

    if (_isTv) {
      if (i == 1) {
        return _TvPairingSlide(
          key: const ValueKey('pair_account'),
          kind: PairingKind.account,
          title: 'Ajoute ta playlist',
          subtitle:
              'Configure ton compte IPTV depuis ton téléphone — la saisie au D-pad serait longue et fastidieuse.',
          onAccountResult: _onAccountReceived,
        );
      }
      // i == 2
      return _TvPairingSlide(
        key: const ValueKey('pair_tmdb'),
        kind: PairingKind.tmdb,
        title: 'Affiches et synopsis (optionnel)',
        subtitle:
            'Colle ton Bearer Token TMDB depuis ton téléphone pour enrichir tes films et séries.',
        onTmdbResult: _onTmdbReceived,
      );
    }

    // Mobile : slides informationnels classiques.
    if (i == 1) {
      return _InfoSlide(
        icon: Icons.link,
        title: 'Ajoute une playlist',
        body:
            'Va dans ⚙️ Paramètres → Comptes IPTV pour saisir une URL M3U complète OU un compte Xtream Codes (serveur + identifiants).',
        accent: kAccentSecondary,
      );
    }
    return _InfoSlide(
      icon: Icons.movie_creation_outlined,
      title: 'Affiches et synopsis (optionnel)',
      body:
          'Génère un Bearer Token TMDB gratuit sur themoviedb.org et colle-le dans Paramètres → Clé API TMDB pour enrichir tes films et séries.',
      accent: kAccentTertiary,
    );
  }
}

// ── Slides ──────────────────────────────────────────────────────────────────

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide();

  @override
  Widget build(BuildContext context) {
    return _InfoSlide(
      icon: Icons.live_tv,
      title: 'Bienvenue sur AetherStream',
      body:
          'Client IPTV multi-comptes pour regarder films, séries et chaînes en direct depuis vos abonnements.',
      accent: kAccentPrimary,
    );
  }
}

class _InfoSlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  const _InfoSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [accent.withAlpha(80), accent.withAlpha(15)],
              ),
              border: Border.all(color: accent.withAlpha(160), width: 2),
              boxShadow: [
                BoxShadow(color: accent.withAlpha(120), blurRadius: 30),
              ],
            ),
            child: Icon(icon, color: accent, size: 60),
          ),
          const SizedBox(height: 40),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide TV intégrant un PairingPage embarqué.
class _TvPairingSlide extends StatelessWidget {
  final PairingKind kind;
  final String title;
  final String subtitle;
  final void Function(PairingAccountResult)? onAccountResult;
  final void Function(PairingTmdbResult)? onTmdbResult;

  const _TvPairingSlide({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.onAccountResult,
    this.onTmdbResult,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _InlinePairing(
              kind: kind,
              onAccountResult: onAccountResult,
              onTmdbResult: onTmdbResult,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper qui intercepte les résultats du `PairingPage` embarqué pour les
/// propager vers le state de l'onboarding (sauvegarde + auto-advance).
class _InlinePairing extends StatelessWidget {
  final PairingKind kind;
  final void Function(PairingAccountResult)? onAccountResult;
  final void Function(PairingTmdbResult)? onTmdbResult;

  const _InlinePairing({
    required this.kind,
    this.onAccountResult,
    this.onTmdbResult,
  });

  @override
  Widget build(BuildContext context) {
    return PairingPage(
      kind: kind,
      embedded: true,
      onResult: (r) {
        if (r is PairingAccountResult) onAccountResult?.call(r);
        if (r is PairingTmdbResult) onTmdbResult?.call(r);
      },
    );
  }
}
