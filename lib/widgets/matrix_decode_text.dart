import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// §matrixFx — Glyphes du brouillage : chiffres, hexadécimal, katakana et
/// signes, comme sur la pluie de fond.
const String kMatrixGlyphs = '0123456789ABCDEFアイウエオカキクケコサシスセソ#\$%&?<>!@=+*';

/// §matrixFx — Le texte tel qu'il s'affiche quand [settled] caractères sont
/// figés (de gauche à droite) : les autres sont tirés au hasard dans
/// [kMatrixGlyphs], sauf les caractères de [keep], figés d'emblée (séparateurs
/// d'un numéro de version : les voir sauter donnerait l'impression d'un numéro
/// instable, pas d'un décodage) et les espaces, qui gardent la forme des mots.
///
/// Fonction pure : c'est elle qu'on teste.
String matrixScramble(
  String target,
  int settled,
  Random rng, {
  String keep = '',
}) {
  final b = StringBuffer();
  for (var i = 0; i < target.length; i++) {
    final String c = target[i];
    if (i < settled || c == ' ' || c == '\n' || keep.contains(c)) {
      b.write(c);
    } else {
      b.write(kMatrixGlyphs[rng.nextInt(kMatrixGlyphs.length)]);
    }
  }
  return b.toString();
}

/// §matrixFx — Un texte qui se « décode » : les caractères défilent puis se
/// figent de gauche à droite en [duration], après [delay]. Extrait de
/// `VersionDiffLine` (§updateBanner) pour servir à toute ligne COURTE d'une
/// carte terminal ; un paragraphe entier ne se lit pas brouillé (fiche
/// §matrixFx), c'est à l'appelant de ne le poser que sur des lignes courtes.
///
/// [builder] rend le texte en cours ([display]) avec le nombre de caractères
/// déjà figés ; par défaut un simple [Text] avec [style]. [enabled] à `false`
/// affiche le texte final tout de suite (profil Léger, §perfSettings).
class MatrixDecodeText extends StatefulWidget {
  const MatrixDecodeText(
    this.text, {
    super.key,
    this.style,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 900),
    this.keep = '',
    this.enabled = true,
    this.builder,
  });

  final String text;
  final TextStyle? style;
  final Duration delay;
  final Duration duration;
  final String keep;
  final bool enabled;
  final Widget Function(BuildContext context, String display, int settled)?
      builder;

  @override
  State<MatrixDecodeText> createState() => _MatrixDecodeTextState();
}

class _MatrixDecodeTextState extends State<MatrixDecodeText> {
  static const _tick = Duration(milliseconds: 45);
  final _rng = Random();
  Timer? _timer;
  Timer? _delay;
  int _settled = 0;
  late String _display;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(MatrixDecodeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.enabled != widget.enabled) {
      _timer?.cancel();
      _delay?.cancel();
      _start();
    }
  }

  void _start() {
    if (!widget.enabled || widget.text.isEmpty) {
      _settled = widget.text.length;
      _display = widget.text;
      return;
    }
    _settled = 0;
    _display = matrixScramble(widget.text, 0, _rng, keep: widget.keep);
    _delay = Timer(widget.delay, () {
      if (!mounted) return;
      final int steps =
          max(1, widget.duration.inMilliseconds ~/ _tick.inMilliseconds);
      var step = 0;
      _timer = Timer.periodic(_tick, (t) {
        step++;
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _settled =
              (widget.text.length * step / steps).floor().clamp(0, widget.text.length);
          _display = matrixScramble(widget.text, _settled, _rng, keep: widget.keep);
        });
        if (_settled >= widget.text.length) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.builder;
    if (b != null) return b(context, _display, _settled);
    return Text(_display, style: widget.style);
  }
}
