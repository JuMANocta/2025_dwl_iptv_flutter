import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/web_console_service.dart';
import 'package:aetherStream/feature/settings/backup_restore_flow.dart';
import 'package:aetherStream/feature/settings/web_console/web_console_page.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';

/// Onboarding affiché une seule fois (§1i + §3c-8 TV + §webConsoleOnly).
///
/// Stocke `onboarding_done_v1=true` dans SharedPreferences une fois fini.
/// L'aiguilleur (`_LaunchDecider` dans main.dart) consulte
/// [OnboardingService.shouldShow] avant la première navigation.
///
/// Sur **TV** (§webConsoleOnly, 2026-08-05) : **2 slides** au lieu de 3.
///   - Slide 1 : Welcome (inchangé)
///   - Slide 2 : Console web embarquée — l'utilisateur scanne UN seul QR et
///     configure playlist ET clé TMDB (et tout le reste) depuis son navigateur.
///
/// Avant, ces deux réglages exigeaient **deux sessions de pairing successives**,
/// chacune limitée à un formulaire unique. La Console web couvrant déjà tout,
/// le troisième slide n'avait plus de raison d'être : un seul scan suffit, et
/// comme le serveur survit à la fermeture de l'écran, le téléphone peut
/// continuer à configurer pendant que la TV est déjà sur l'accueil.
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

  /// §webConsoleOnly — Message de confirmation affiché sur le slide console
  /// quand une action arrive du téléphone (la TV doit montrer que ça a marché,
  /// l'utilisateur regarde son écran, pas la télé).
  String? _consoleStatus;

  /// Garde anti-double-appel : plusieurs actions peuvent arriver coup sur coup
  /// depuis le navigateur (compte + TMDB), or `_finish` ne doit courir qu'une
  /// fois — sinon `onFinish` navigue deux fois.
  bool _finishing = false;

  bool get _isTv => PlatformTv.isTv;

  /// TV : Welcome + Console web. Mobile : les 3 slides informationnels.
  int get _slideCount => _isTv ? 2 : 3;

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
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

  /// §webConsoleOnly — Une action vient d'être appliquée depuis le navigateur.
  ///
  /// La Console web enregistre elle-même (compte, token…) : contrairement au
  /// pairing, il n'y a rien à sauvegarder ici. On se contente de confirmer à
  /// l'écran, puis de terminer l'onboarding dès qu'un **compte** existe — c'est
  /// la seule config qui bloque le démarrage de l'app. Le serveur restant actif
  /// en arrière-plan, le téléphone peut poursuivre (TMDB, thème…) pendant que
  /// la TV bascule sur l'accueil.
  void _onConsoleEvent(WebConsoleEvent event) {
    if (event.isAccountChange) {
      setState(() => _consoleStatus = '✅ Playlist enregistrée');
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _finish();
      });
      return;
    }
    if (event.isTmdbChange) {
      setState(() => _consoleStatus = '✅ Clé TMDB enregistrée');
    }
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
                child: FocusableCard(
                  onTap: _finish,
                  scaleOnFocus: false,
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
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: _slideCount,
                  // §webConsoleOnly — Le swipe redevient libre : la session
                  // Console web survit au changement de slide (le serveur ne
                  // s'arrête qu'explicitement), contrairement au pairing qu'un
                  // swipe accidentel faisait perdre.
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
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, _index == 0 ? 8 : 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  // §dpadAlign — L'onboarding n'avait AUCUN focusable : au
                  // premier lancement sur TV, la télécommande ne pouvait rien
                  // sélectionner (ni Suivant, ni Passer). Le CTA prend le focus
                  // d'entrée, les deux autres boutons deviennent atteignables.
                  child: FocusableCard(
                    autofocus: true,
                    scaleOnFocus: false,
                    borderRadius: BorderRadius.circular(12),
                    onTap: _next,
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
                    // §webConsoleOnly — Le bouton reste visible sur le slide
                    // console : l'utilisateur peut entrer sans configurer (il
                    // retrouvera la console dans les Paramètres) au lieu d'être
                    // coincé à attendre un scan, comme c'était le cas avec le
                    // pairing en auto-advance seul.
                    child: Text(isLast ? 'Commencer' : 'Suivant'),
                    ),
                  ),
                ),
              ),
              // §restore — Slide d'accueil uniquement : récupérer une sauvegarde.
              if (_index == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FocusableCard(
                    onTap: _onRestoreTap,
                    scaleOnFocus: false,
                    child: TextButton.icon(
                      onPressed: _onRestoreTap,
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('J\'ai déjà une sauvegarde (.aether)'),
                      style: TextButton.styleFrom(
                        foregroundColor: kAccentSecondary,
                      ),
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
      // i == 1 — Console web : playlist + TMDB + tout le reste en un seul scan.
      return _TvConsoleSlide(
        key: const ValueKey('console'),
        status: _consoleStatus,
        onEvent: _onConsoleEvent,
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

/// §webConsoleOnly — Slide TV intégrant la **Console web** embarquée.
///
/// Remplace les deux anciens slides de pairing : un seul QR donne accès au
/// panneau complet (playlist, TMDB, thème, sauvegarde…), au lieu d'enchaîner
/// deux formulaires mono-champ.
class _TvConsoleSlide extends StatelessWidget {
  /// Confirmation poussée par le state parent quand le téléphone valide.
  final String? status;
  final void Function(WebConsoleEvent) onEvent;

  const _TvConsoleSlide({super.key, this.status, required this.onEvent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Configure depuis ton téléphone',
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
              'Scanne ce QR code : tu pourras ajouter ta playlist, ta clé TMDB '
              'et régler le reste depuis ton navigateur — la saisie au D-pad '
              'serait longue et fastidieuse.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            Text(
              status!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kSuccess,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: WebConsolePage(
              embedded: true,
              initialView: 'accounts',
              onEvent: onEvent,
            ),
          ),
        ],
      ),
    );
  }
}
