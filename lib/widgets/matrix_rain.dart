import 'dart:math';

import 'package:flutter/material.dart';

import '../core/themes/colors.dart';

/// §updateBanner — Pluie « Matrix » réutilisable.
///
/// **Pourquoi ce fichier existe** : le painter riche (traîne dégradée,
/// katakana) vivait en privé dans `terminal_download_dialog.dart`, tandis que
/// le dialogue de mise à jour se contentait d'une version appauvrie derrière sa
/// seule barre de progression — deux pluies pour un même effet, dont une moins
/// belle. Extraite ici, les deux partagent la bonne.
///
/// ⚠️ [alpha] existe pour servir de FOND de dialogue : à pleine intensité la
/// pluie rend illisible le texte par-dessus. ~45 laisse l'effet perceptible
/// sans gêner la lecture.


/// Glyphes de la pluie : chiffres, katakana, capitales latines, ponctuation.
const String _kMatrixChars =
    '01234567890'
    'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '#\$%&?<>!@=+*:-|';

class _RainDrop {
  final double xFraction;
  final double phase;
  final double speed;
  const _RainDrop(
      {required this.xFraction, required this.phase, required this.speed});
}

class MatrixRain extends StatefulWidget {
  final bool active;

  /// Opacité globale (0-255) — voir la note de classe.
  final int alpha;
  const MatrixRain({super.key, this.active = true, this.alpha = 255});

  @override
  State<MatrixRain> createState() => MatrixRainState();
}

class MatrixRainState extends State<MatrixRain>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_RainDrop> _drops;

  static const int _dropCount = 14;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _drops = List.generate(
      _dropCount,
      (i) => _RainDrop(
        xFraction: i / _dropCount + rng.nextDouble() * 0.04,
        phase: rng.nextDouble(),
        // Speed entier obligatoire : garantit (1.0*n + phase) % 1.0 == phase
        // → pas de saut de position au rebouclage du controller
        speed: (rng.nextInt(3) + 1).toDouble(), // 1x, 2x ou 3x par cycle
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void didUpdateWidget(MatrixRain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => SizedBox.expand(
        child: CustomPaint(
          painter: _MatrixRainPainter(_drops, _controller.value, widget.alpha),
        ),
      ),
    );
  }
}

class _MatrixRainPainter extends CustomPainter {
  final List<_RainDrop> drops;
  final double animValue;

  /// Opacité globale — voir [MatrixRain.alpha].
  final int alpha;

  const _MatrixRainPainter(this.drops, this.animValue, this.alpha);

  @override
  void paint(Canvas canvas, Size size) {
    const chars = _kMatrixChars;
    const trailSteps = 8;
    const charHeight = 9.0;

    for (int i = 0; i < drops.length; i++) {
      final drop = drops[i];
      final x = drop.xFraction * size.width;
      final yProgress = (animValue * drop.speed + drop.phase) % 1.0;
      final yHead = yProgress * (size.height + trailSteps * charHeight) - trailSteps * charHeight;

      // Traîne dégradée
      for (int j = 1; j <= trailSteps; j++) {
        final yTrail = yHead - j * charHeight;
        if (yTrail < 0 || yTrail > size.height) continue;
        // ⚠️ Nommée `trailOpacity` et non `alpha` : le champ `alpha` de la
        // classe module l'ensemble, les confondre annulerait le réglage.
        final trailOpacity = (1.0 - j / trailSteps) * 0.12 * (alpha / 255);
        canvas.drawRect(
          Rect.fromLTWH(x - 4, yTrail, 10, charHeight),
          Paint()..color = Color.fromRGBO(0, 180, 0, trailOpacity),
        );
      }

      // Caractère de tête
      if (yHead >= -charHeight && yHead <= size.height) {
        final charIndex =
            ((animValue * 30 + i * 4.3 + drop.phase * 10).floor()).abs() % chars.length;
        final tp = TextPainter(
          text: TextSpan(
            text: chars[charIndex],
            style: TextStyle(
              color: kSuccess.withAlpha((140 * alpha / 255).round()),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x - 4, yHead));
      }
    }
  }

  @override
  bool shouldRepaint(_MatrixRainPainter old) =>
      old.animValue != animValue || old.alpha != alpha;
}
