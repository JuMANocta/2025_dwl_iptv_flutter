import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/themes/colors.dart';
import '../../widgets/matrix_decode_text.dart';

/// §updateBanner — Les deux lignes de version de la carte de mise à jour : la
/// version installée en clair, la nouvelle « décodée » caractère par
/// caractère, la partie qui CHANGE mise en évidence.
///
/// §matrixFx — Le décodage lui-même vit dans [MatrixDecodeText] (extrait d'ici
/// pour servir au dialogue de téléchargement) ; ce widget ne garde que ce qui
/// n'a de sens qu'ici : le préfixe commun aux deux versions, atténué.
class VersionDiffLine extends StatelessWidget {
  final String localVersion;
  final String remoteVersion;

  const VersionDiffLine({
    super.key,
    required this.localVersion,
    required this.remoteVersion,
  });

  int get _commonPrefix {
    final a = localVersion;
    final b = remoteVersion;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> CURRENT : $localVersion',
          style: mono.copyWith(color: kTermGreenDim),
        ),
        const SizedBox(height: 2),
        MatrixDecodeText(
          remoteVersion,
          duration: const Duration(milliseconds: 1200),
          keep: '.+',
          builder: (context, display, settled) {
            final done = settled >= remoteVersion.length;
            return RichText(
              text: TextSpan(
                style: mono.copyWith(color: kTermGreenYellow),
                children: [
                  const TextSpan(text: '> RELEASE : '),
                  // Préfixe commun : atténué, il n'apporte rien.
                  TextSpan(
                    text: display.substring(0, min(common, display.length)),
                    style: mono.copyWith(color: kTermOlive),
                  ),
                  // ⚠️ La partie qui CHANGE, en vert vif + glow : c'est la
                  // seule information que l'utilisateur cherche dans ces deux
                  // lignes.
                  TextSpan(
                    text: display.substring(min(common, display.length)),
                    style: mono.copyWith(
                      color: done ? kAccentPrimary : kTermGreenBright,
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
            );
          },
        ),
      ],
    );
  }
}
