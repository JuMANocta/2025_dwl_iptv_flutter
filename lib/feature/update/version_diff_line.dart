import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/themes/colors.dart';

/// §updateBanner — Deux lignes de version, dont la nouvelle se « décode » à la
/// manière de Matrix, avec la PARTIE QUI CHANGE mise en évidence.
///
/// **Le manque qu'elle comble** : le bandeau annonçait `> REMOTE : v1.15.9`
/// sans jamais dire de quelle version on part. Impossible de savoir si la mise
/// à jour apporte un correctif ou six mois de travail — ni même si on ne l'a
/// pas déjà installée.
///
/// ⚠️ **Le préfixe commun est calculé, pas deviné** : sur `1.15.9+102` →
/// `1.15.10+103`, seul `1.15.` est commun. Surligner « tout après le dernier
/// point » se tromperait dès qu'un chiffre gagne une décimale — cas fréquent,
/// et précisément celui où l'utilisateur a besoin de voir ce qui bouge.
class VersionDiffLine extends StatefulWidget {
  final String localVersion;
  final String remoteVersion;

  const VersionDiffLine({
    super.key,
    required this.localVersion,
    required this.remoteVersion,
  });

  @override
  State<VersionDiffLine> createState() => _VersionDiffLineState();
}

class _VersionDiffLineState extends State<VersionDiffLine> {
  static const _glyphs = '0123456789ABCDEFアイウエオカキクケコサシスセソ#\$%&?<>!@=+*';
  static const _tick = Duration(milliseconds: 45);

  /// Durée totale du décodage. Assez long pour être vu, assez court pour ne pas
  /// retarder quelqu'un qui veut juste appuyer sur « installer ».
  static const _total = Duration(milliseconds: 1200);

  final _rng = Random();
  Timer? _timer;

  /// Nombre de caractères déjà FIGÉS, de gauche à droite.
  int _settled = 0;
  String _display = '';

  String get _target => widget.remoteVersion;

  @override
  void initState() {
    super.initState();
    _display = _scramble(0);
    final steps = _total.inMilliseconds ~/ _tick.inMilliseconds;
    var step = 0;
    _timer = Timer.periodic(_tick, (t) {
      step++;
      // Progression linéaire du figeage : gauche → droite.
      final settled = (_target.length * step / steps).floor();
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _settled = settled.clamp(0, _target.length);
        _display = _scramble(_settled);
      });
      if (_settled >= _target.length) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Les [settled] premiers caractères sont les vrais, le reste défile.
  String _scramble(int settled) {
    final b = StringBuffer();
    for (var i = 0; i < _target.length; i++) {
      if (i < settled) {
        b.write(_target[i]);
      } else if (_target[i] == '.' || _target[i] == '+') {
        // On fige d'emblée les séparateurs : les voir sauter donnerait
        // l'impression d'un numéro de version instable, pas d'un décodage.
        b.write(_target[i]);
      } else {
        b.write(_glyphs[_rng.nextInt(_glyphs.length)]);
      }
    }
    return b.toString();
  }

  /// Longueur du préfixe COMMUN aux deux versions.
  int get _commonPrefix {
    final a = widget.localVersion;
    final b = _target;
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.sourceCodePro(fontSize: 12);
    final common = _commonPrefix;
    final done = _settled >= _target.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> CURRENT : ${widget.localVersion}',
          style: mono.copyWith(color: const Color(0xFF00AA00)),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: mono.copyWith(color: const Color(0xFFADFF2F)),
            children: [
              const TextSpan(text: '> RELEASE : '),
              // Préfixe commun : atténué, il n'apporte rien.
              TextSpan(
                text: _display.substring(0, min(common, _display.length)),
                style: mono.copyWith(color: const Color(0xFF7A9A3F)),
              ),
              // ⚠️ La partie qui CHANGE, en vert vif + glow : c'est la seule
              // information que l'utilisateur cherche dans ces deux lignes.
              TextSpan(
                text: _display.substring(min(common, _display.length)),
                style: mono.copyWith(
                  color: done ? kAccentPrimary : const Color(0xFF33FF33),
                  fontWeight: FontWeight.bold,
                  shadows: done
                      ? [
                          Shadow(
                              color: kAccentPrimary.withAlpha(160),
                              blurRadius: 8),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
