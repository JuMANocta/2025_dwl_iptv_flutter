import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/platform_tv.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../l10n/l10n_ext.dart';

// ─── Briques de feuille du lecteur ──────────────────────────────────────────
//
// §playerPanel (2026-09-22) — Les feuilles d'OPTIONS du lecteur sont parties :
// le panneau ⚙ (`showPlayerOptions`) et ses sous-menus Format d'image,
// Vitesse, Qualité et Infos vidéo. Leurs réglages sont des boutons de la
// rangée d'options, dans l'image (`player_option_bar.dart`), au téléphone
// comme sur TV.
//
// Restent ici les trois briques qu'utilise la feuille « Diffuser »
// (`cast_sheet.dart`) : [OptionsSheetBody], [OptionSheetRow] et
// [BackToVideoRow]. Le nom du fichier est historique.

/// §tvOptionsBack — « Revenir à la vidéo », la sortie explicite d'une feuille
/// du lecteur.
///
/// **Pourquoi elle existe** : à la télécommande, un modal sans bouton de
/// fermeture n'a d'autre issue que la touche Retour — et c'est précisément ce
/// qui faisait sortir du FILM (signalement du 2026-09-08). ⚠️ Les SOUS-MENUS
/// (Vitesse, Format d'image) sont dans le même cas dès qu'on y entre sans
/// vouloir changer de valeur : c'est le second signalement, du 2026-09-09.
///
/// ⚠️ **À poser en DERNIER, jamais en premier.** `TvAutofocusFirst` donne le
/// focus au premier élément focusable du modal : « fermer » en tête ferait de
/// la fermeture l'action par défaut du panneau qu'on vient d'ouvrir.
///
/// ⚠️ **TÉLÉVISEUR UNIQUEMENT** (signalé pendant la recette du 2026-09-09 :
/// « c'est pas pour la version téléphone, seulement pour la version PC, car
/// sur téléphone un clic sur l'écran fait un pseudo retour »). Au doigt,
/// taper hors du cadre referme déjà la feuille : la ligne n'y serait que du
/// bruit, une entrée de plus à lire dans un menu. **À la télécommande, il
/// n'y a pas de « hors du cadre »** — le curseur ne peut atteindre que des
/// éléments focusables. C'est la même famille de décision que §pipPhone et
/// §nowPlaying : une affordance qui n'a de sens que sur une seule surface.
class BackToVideoRow extends StatelessWidget {
  const BackToVideoRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => !PlatformTv.isTv
      ? const SizedBox.shrink()
      : OptionSheetRow(
        icon: Icons.keyboard_return_rounded,
        accent: kAccentSecondary,
        title: context.l10n.optBackToVideo,
        subtitle: context.l10n.optBackToVideoSub,
        onTap: onTap,
      );
}

class OptionsSheetBody extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const OptionsSheetBody({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre vide = pas d'en-tête du tout : garder l'icône seule
                // laisserait une pastille orpheline au-dessus du contenu.
                if (title.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(icon, color: kAccentPrimary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptionSheetRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const OptionSheetRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: FocusableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(26) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: accent.withAlpha(70),
                        blurRadius: 14,
                        spreadRadius: -3),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withAlpha(90)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withAlpha(140)),
            ],
          ),
        ),
      ),
    );
  }
}
