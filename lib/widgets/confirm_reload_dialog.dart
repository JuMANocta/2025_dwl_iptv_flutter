import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../data/services/playlist_reload_service.dart';
import 'tv/tv_adaptive_modal.dart';
import '../l10n/l10n_ext.dart';

/// §reloadKeep — Dialogue « Recharger ? » pour une liste encore fraîche.
///
/// Extrait de `AccountsPage._confirmReload` pour que le ↻ de l'accueil pose la
/// MÊME question, avec le même texte et le même seuil
/// ([PlaylistReloadService.shouldConfirm]). Rend `true` si l'utilisateur
/// confirme, `false` ou `null` sinon.
///
/// §safeFocus — Sur TV, le focus initial se pose sur **Annuler** : la touche
/// OK pressée par réflexe ne déclenche pas un téléchargement complet.
Future<bool?> showConfirmReloadDialog(
  BuildContext context, {
  required String accountLabel,
  required Duration age,
}) {
  final String ageStr = PlaylistReloadService.formatAge(age);
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.acctReloadTitle),
      content: Text(
        ctx.l10n.acctReloadBody(accountLabel, ageStr),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            ctx.l10n.acctReload,
            style: TextStyle(color: kWarning, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
