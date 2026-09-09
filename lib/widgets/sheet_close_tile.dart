import 'package:flutter/material.dart';

import '../core/utils/platform_tv.dart';
import '../l10n/l10n_ext.dart';

/// §tvOptionsBack — La sortie explicite d'une feuille d'actions.
///
/// **Pourquoi elle existe.** À la télécommande, un modal dont toutes les lignes
/// DÉCLENCHENT quelque chose est une impasse : il n'y a plus qu'à appuyer sur
/// Retour, et c'est précisément ce geste qui pose problème sur TV (§dpadBack,
/// signalements des 8 et 9 septembre 2026 — « il faut un bouton pour annuler et
/// revenir »). Une feuille de choix doit toujours offrir de **ne rien choisir**.
///
/// Pendant du `BackToVideoRow` de `player_options_sheet.dart`, pour les
/// feuilles qui ne sont PAS dans le lecteur : le libellé y dit « Fermer », pas
/// « Revenir à la vidéo » — il n'y a pas de vidéo derrière.
///
/// ⚠️ **À poser en DERNIER, jamais en premier.** `TvAutofocusFirst` donne le
/// focus au premier élément focusable du modal : « fermer » en tête ferait de
/// la fermeture l'action par défaut de la feuille qu'on vient d'ouvrir.
///
/// ⚠️ **TÉLÉVISEUR UNIQUEMENT** (signalé pendant la recette du 2026-09-09 :
/// « c'est pas pour la version téléphone, seulement pour la version PC, car
/// sur téléphone un clic sur l'écran fait un pseudo retour »). Au doigt,
/// taper hors du cadre referme déjà la feuille : la ligne n'y serait que du
/// bruit, une entrée de plus à lire dans un menu. **À la télécommande, il
/// n'y a pas de « hors du cadre »** — le curseur ne peut atteindre que des
/// éléments focusables. C'est la même famille de décision que §pipPhone et
/// §nowPlaying : une affordance qui n'a de sens que sur une seule surface.
class SheetCloseTile extends StatelessWidget {
  const SheetCloseTile({super.key, this.onTap});

/// Par défaut, dépile la route de la feuille. Passer un callback quand la
/// feuille doit faire autre chose en plus (rendre un résultat, par exemple).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!PlatformTv.isTv) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
      title: Text(context.l10n.sheetClose),
      subtitle: Text(
        context.l10n.sheetCloseSub,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
      onTap: onTap ?? () => Navigator.of(context).pop(),
    );
  }
}
