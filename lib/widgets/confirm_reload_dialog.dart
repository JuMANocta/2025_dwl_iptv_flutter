import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../data/services/playlist_reload_service.dart';
import 'tv/tv_adaptive_modal.dart';

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
      title: const Text('Recharger ?'),
      content: Text(
        'La playlist de "$accountLabel" a été téléchargée il y a $ageStr.\n'
        'Recharger quand même depuis le serveur ?',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Recharger',
            style: TextStyle(color: kWarning, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
