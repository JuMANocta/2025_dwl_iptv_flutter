import 'dart:async';

import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../data/models/stream_account.dart';
import '../data/services/playlist_reload_service.dart';
import '../l10n/l10n_ext.dart';
import 'tv/tv_adaptive_modal.dart';

/// §reloadScope — Recharger **toutes** les listes : une seule implémentation.
///
/// **Pourquoi ce fichier existe.** Le ↻ de l'accueil ne rechargeait que la
/// liste PRINCIPALE, et rien ne le disait : l'utilisateur voyait une liste se
/// rafraîchir, les autres rester en l'état, et concluait — à raison — que le
/// bouton ne faisait pas ce qu'il annonce. Le rechargement complet existait
/// pourtant, mais uniquement dans Paramètres → Comptes, dans un `State` de
/// widget : le reprendre depuis l'accueil imposait soit de le dupliquer, soit
/// de piloter une page depuis une autre. Extrait ici, il sert les deux entrées
/// avec la même question, la même progression et le même bilan.
///
/// Rend `null` si l'utilisateur annule (rien n'a été téléchargé), sinon le
/// bilan — que l'appelant affiche : c'est lui qui sait où mettre le message.
///
/// ⚠️ **Séquentiel, jamais en parallèle.** Chaque catalogue est analysé EN RAM ;
/// quatre listes de 80 000 entrées décodées en même temps mettent une Fire
/// Stick à genoux. C'est aussi ce que raconte `PlaylistFleetService` : sur des
/// panels limités à une connexion, la lenteur fabrique le parallélisme qui
/// aggrave la lenteur.
Future<ReloadBatchResult?> showReloadAllFlow(
  BuildContext context, {
  required List<StreamAccount> accounts,
  required String? priorityAccountId,
}) async {
  if (accounts.isEmpty) return null;
  final l10n = context.l10n;

  // ── UNE seule confirmation, en tête ────────────────────────────────────
  // ⚠️ La confirmation par liste se déclenche quand la playlist a moins de
  // 24 h. Appliquée en boucle, elle poserait la question quatre fois. On
  // demande une fois, en NOMMANT les listes récentes — c'est la seule
  // information qui pourrait faire changer d'avis.
  final recent = <String>[];
  for (final a in accounts) {
    final age = await PlaylistReloadService.cacheAge(a.id);
    if (age != null && age < PlaylistReloadService.confirmBelow) {
      recent.add(a.label);
    }
  }
  if (!context.mounted) return null;

  final bool? ok = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.reloadAllTitle),
      content: Text(recent.isEmpty
          ? l10n.reloadAllBody(accounts.length)
          : l10n.reloadAllBodyRecent(accounts.length, recent.join(', '))),
      actions: [
        TextButton(
          // §safeFocus — Sur TV, le focus initial se pose sur « Annuler » : la
          // touche OK pressée par réflexe ne lance pas plusieurs minutes de
          // téléchargement.
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.reloadAllConfirm,
            style: TextStyle(color: kWarning, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;

  // Boîte de progression : le geste dure plusieurs minutes, un spinner muet
  // laisserait croire à un blocage.
  final progress = ValueNotifier<String>(l10n.reloadAllPreparing);
  final NavigatorState navigator = Navigator.of(context);
  unawaited(showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false, // on ne quitte pas un lot en cours par mégarde
      child: AlertDialog(
        title: Text(l10n.reloadAllProgressTitle),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, v, __) => Text(v),
              ),
            ),
          ],
        ),
      ),
    ),
  ));

  final succeeded = <String>[];
  final failed = <String, String>{};

  for (var i = 0; i < accounts.length; i++) {
    final a = accounts[i];
    progress.value = l10n.reloadAllStep(i + 1, accounts.length, a.label);
    try {
      // ⚠️ [isPriority] change le CHEMIN de téléchargement : le compte
      // principal passe par `downloadCurrentM3U()`, qui produit des messages
      // d'erreur précis. Uniformiser ferait perdre le diagnostic sur la liste
      // qui compte le plus.
      await PlaylistReloadService.reloadAccount(
        a,
        isPriority: a.id == priorityAccountId,
      );
      succeeded.add(a.label);
    } catch (e) {
      // ⚠️ Un échec n'arrête PAS le lot : une liste injoignable ne doit pas
      // empêcher de rafraîchir les autres — c'est exactement le problème qu'on
      // cherche à supprimer.
      failed[a.label] = e.toString();
      debugPrint('❌ §reloadAll — « ${a.label} » : $e');
    }
  }

  progress.dispose();
  if (navigator.canPop()) navigator.pop(); // ferme la boîte de progression

  final result = ReloadBatchResult(succeeded: succeeded, failed: failed);
  debugPrint('🔄 §reloadAll — ${result.summary}');
  return result;
}
