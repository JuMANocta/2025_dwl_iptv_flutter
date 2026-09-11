import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../core/utils/app_snackbar.dart';
import '../core/utils/platform_tv.dart';
import 'tv/tv_adaptive_modal.dart';
import '../l10n/l10n_ext.dart';

/// §undoTv — Une action réversible, présentée selon l'appareil.
///
/// **Le défaut corrigé** : les annulations posées le 2026-09-03 (effacer
/// l'historique, réinitialiser les réglages, oublier une reprise) passent par
/// l'action d'une `SnackBar`. Vérifié à l'AVD TV : **cette action n'est pas
/// atteignable à la télécommande** — ↓ depuis la barre du haut va à la tuile
/// suivante, jamais dans la snackbar. Sur téléviseur, ces annulations étaient
/// donc décoratives : l'action était irréversible sans qu'on le dise.
///
/// La solution n'est pas de rendre la snackbar focusable — elle disparaît au
/// bout de cinq secondes, ce qui ferait un piège de plus. Sur TV on **demande
/// avant** (avec le focus sur « Annuler », §safeFocus) ; au doigt on garde
/// l'annulation **après**, qui ne coupe pas le geste.
///
/// ⚠️ [onUndo] doit être capable de restaurer l'état APRÈS coup : capturer
/// l'instantané **avant** d'appeler cette fonction, jamais dedans.
///
/// [isTv] force la branche choisie — réservé aux tests (`PlatformTv.isTv` est
/// un cache statique alimenté par un channel natif, donc toujours faux sous
/// `flutter test` : sans cette couture, la moitié TV de cette fonction — celle
/// qui corrige le défaut — ne serait vérifiable que sur un appareil). Même
/// idiome que `TvAutofocusFirst.enabled`.
Future<bool> confirmOrUndo(
  BuildContext context, {
  required String title,
  required String question,
  required String confirmLabel,
  required String doneMessage,
  required Future<void> Function() action,
  required VoidCallback onUndo,
  bool destructive = true,
  bool? isTv,
  // Recette S25 du 2026-09-11 — Demander AVANT sur tous les appareils : pour
  // une perte coûteuse à refaire (une clé de ~220 caractères), une annulation
  // de 5 s dans une snackbar se rate trop facilement (« pas eu d'Annuler
  // possible, ça a détruit la clé »).
  bool alwaysAsk = false,
}) async {
  if (alwaysAsk || (isTv ?? PlatformTv.isTv)) {
    final bool ok = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(question),
            actions: [
              TextButton(
                // §safeFocus — Le focus s'ouvre sur le bouton SÛR : à la
                // télécommande, OK est le geste réflexe.
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, false),
                // ⚠️ `L10n.current` et pas `context.l10n` : ce dialogue peut se
                // construire sous un contexte sans `Localizations` (tests).
                child: Text(L10n.current.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  confirmLabel,
                  style: destructive ? TextStyle(color: kError) : null,
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return false;
    await action();
    if (context.mounted) AppSnackBar.show(context, doneMessage);
    return true;
  }

  // Tactile : on agit, et on laisse cinq secondes pour revenir en arrière.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  await action();
  AppSnackBar.showVia(
    messenger,
    SnackBar(
      content: Text(doneMessage),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
          label: L10n.current.commonCancel, onPressed: onUndo),
    ),
  );
  return true;
}
