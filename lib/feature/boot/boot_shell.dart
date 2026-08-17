import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/themes/aether_theme_extension.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';

/// §bootShell — Le décor commun à TOUS les états de démarrage.
///
/// **Ce qu'il corrige.** Le démarrage comptait quatre états et un seul était
/// soigné : le chargement. L'erreur affichait une icône `Colors.red` **codée en
/// dur** (donc hors thème) avec des boutons Material nus, et l'écran « aucun
/// compte » sortait une `AppBar` sans wordmark ni glow. Or ce sont précisément
/// les moments de doute — « ça a planté ? », « je fais quoi ? » — qui étaient
/// les plus négligés.
///
/// **Le principe.** Le cadre ne bouge pas ; seul le contenu change. Passer de
/// « chargement » à « erreur » n'est pas un changement d'écran mais un
/// changement de contenu à l'intérieur d'une composition stable. C'est ça qui
/// donne l'impression d'une application qui se tient.
///
/// **Le thème est roi** : toutes les couleurs viennent du `ColorScheme` et de
/// [AetherThemeExtension], donc des 9 presets de l'utilisateur. L'intensité des
/// effets suit `glowIntensity` — le preset Minimaliste (glow 0) obtient une
/// version sobre de cet écran, sans halo ni scanlines, sans que la composition
/// s'effondre.
class BootShell extends StatefulWidget {
  /// Contenu de l'état courant (journal, message d'erreur, actions…).
  final Widget child;

  /// Identifie l'état affiché — sert de clé à l'`AnimatedSwitcher` : c'est ce
  /// qui déclenche le fondu quand on passe d'un état à l'autre.
  final String stateKey;

  const BootShell({super.key, required this.child, required this.stateKey});

  @override
  State<BootShell> createState() => _BootShellState();
}

class _BootShellState extends State<BootShell>
    with SingleTickerProviderStateMixin {
  /// §bootMotion — Animation d'ENTRÉE, jouée une seule fois.
  ///
  /// Le démarrage est le moment où le CPU est le plus chargé (réseau puis
  /// parsing en isolate) : tout ce qui tourne en continu ici ralentirait
  /// réellement le boot au lieu de masquer l'attente. D'où une seule animation
  /// one-shot, puis plus rien.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _intro, curve: Curves.easeOut);
  late final Animation<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      /* le pied de page reste vide, sans conséquence */
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final double glow = ext?.glowIntensity ?? 0.4;
    final bool isTv = PlatformTv.isTv;

    // Le `textScaler` étant clampé à 1.0 sur TV (cf. main.dart), rien ne
    // grossit tout seul : les tailles TV doivent être explicites.
    final double wordmarkSize = isTv ? 88 : 56;
    final double blockWidth = isTv ? 620 : 340;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.1,
            colors: [
              cs.primary.withValues(alpha: 0.10 + 0.06 * glow),
              cs.surface,
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Décor peint UNE SEULE FOIS, isolé du reste de l'arbre : le
            // journal se reconstruit à chaque étape, pas ces couches-là.
            if (glow > 0)
              RepaintBoundary(
                child: CustomPaint(
                  painter: _ScanlinesPainter(
                    color: cs.primary,
                    intensity: glow,
                  ),
                ),
              ),
            RepaintBoundary(
              child: CustomPaint(painter: _VignettePainter(color: cs.surface)),
            ),
            SafeArea(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _rise,
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      _Wordmark(size: wordmarkSize, glow: glow),
                      const SizedBox(height: 14),
                      _GradientRule(width: blockWidth * 0.55),
                      SizedBox(height: isTv ? 44 : 34),
                      // Le contenu de l'état, sur la MÊME largeur que le
                      // wordmark et le filet : c'est l'alignement qui fait le
                      // rendu « pro », plus que les effets.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: blockWidth),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOut,
                          child: KeyedSubtree(
                            key: ValueKey<String>(widget.stateKey),
                            child: widget.child,
                          ),
                        ),
                      ),
                      const Spacer(flex: 4),
                      if (_version.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            _version,
                            style: GoogleFonts.sourceCodePro(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                              fontSize: isTv ? 13 : 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wordmark AETHERSTREAM — l'ancre d'identité de l'écran.
class _Wordmark extends StatelessWidget {
  final double size;
  final double glow;

  const _Wordmark({required this.size, required this.glow});

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Text(
      'AetherStream',
      style: GoogleFonts.vt323(
        color: primary,
        fontSize: size,
        letterSpacing: size * 0.07,
        height: 1.0,
        shadows: glow <= 0
            ? null
            : [
                Shadow(
                  color: primary.withValues(alpha: 0.70 * glow),
                  blurRadius: 18 * glow,
                ),
                Shadow(
                  color: primary.withValues(alpha: 0.45 * glow),
                  blurRadius: 34 * glow,
                ),
              ],
      ),
    );
  }
}

/// Filet dégradé sous le wordmark — reprend [kAetherGradient], le dégradé
/// signature de l'app, jusqu'ici utilisé partout SAUF au démarrage.
class _GradientRule extends StatelessWidget {
  final double width;

  const _GradientRule({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        gradient: kAetherGradient,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Voile CRT : lignes horizontales très fines, peintes une fois.
///
/// C'est le seul « effet » de l'écran, et il ne coûte qu'un `paint` — pas une
/// animation. Son opacité suit `glowIntensity`, donc il disparaît sur le preset
/// Minimaliste au lieu d'imposer un style que l'utilisateur n'a pas choisi.
class _ScanlinesPainter extends CustomPainter {
  final Color color;
  final double intensity;

  const _ScanlinesPainter({required this.color, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.035 * intensity)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinesPainter old) =>
      old.color != color || old.intensity != intensity;
}

/// Assombrissement des bords : recentre le regard sur le bloc central.
class _VignettePainter extends CustomPainter {
  final Color color;

  const _VignettePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.55),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.color != color;
}
