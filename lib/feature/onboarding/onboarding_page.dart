import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/core/themes/colors.dart';

/// Onboarding 3 écrans affichés une seule fois (§1i).
///
/// Stocke `onboarding_done_v1=true` dans SharedPreferences une fois fini.
/// L'aiguilleur (`_LaunchDecider` dans main.dart) consulte
/// [OnboardingService.shouldShow] avant la première navigation.
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

class _OnboardSlide {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  const _OnboardSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
}

class OnboardingPage extends StatefulWidget {
  /// Callback appelé quand l'utilisateur termine ("Commencer") ou skip.
  /// Le parent décide ensuite où naviguer (ex: AccountsPage pour ajouter un compte).
  final VoidCallback onFinish;
  const OnboardingPage({super.key, required this.onFinish});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _index = 0;

  // Non-const car les accents sont des getters (thème dynamique).
  static final List<_OnboardSlide> _slides = [
    _OnboardSlide(
      icon: Icons.live_tv,
      title: 'Bienvenue sur AetherStream',
      body:
          'Client IPTV multi-comptes pour regarder films, séries et chaînes en direct depuis vos abonnements.',
      accent: kAccentPrimary,
    ),
    _OnboardSlide(
      icon: Icons.link,
      title: 'Ajoute une playlist',
      body:
          'Va dans ⚙️ Paramètres → Comptes IPTV pour saisir une URL M3U complète OU un compte Xtream Codes (serveur + identifiants).',
      accent: kAccentSecondary,
    ),
    _OnboardSlide(
      icon: Icons.movie_creation_outlined,
      title: 'Affiches et synopsis (optionnel)',
      body:
          'Génère un Bearer Token TMDB gratuit sur themoviedb.org et colle-le dans Paramètres → Comptes IPTV pour enrichir tes films et séries.',
      accent: kAccentTertiary,
    ),
  ];

  Future<void> _finish() async {
    await OnboardingService.markDone();
    if (!mounted) return;
    widget.onFinish();
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
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
    final isLast = _index == _slides.length - 1;

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
                        color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                ),
              ),
              // Dots indicator
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active ? kAccentPrimary : cs.outline.withAlpha(80),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _OnboardSlide slide;
  const _SlideView({required this.slide});

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
                colors: [slide.accent.withAlpha(80), slide.accent.withAlpha(15)],
              ),
              border: Border.all(color: slide.accent.withAlpha(160), width: 2),
              boxShadow: [
                BoxShadow(color: slide.accent.withAlpha(120), blurRadius: 30),
              ],
            ),
            child: Icon(slide.icon, color: slide.accent, size: 60),
          ),
          const SizedBox(height: 40),
          Text(
            slide.title,
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
            slide.body,
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
