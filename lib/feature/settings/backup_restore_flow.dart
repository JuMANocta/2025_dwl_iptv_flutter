import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/services/backup_service.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import '../../l10n/l10n_ext.dart';

/// Flux UI complet de restauration d'une sauvegarde `.aether` (§10), extrait
/// pour être réutilisable depuis `BackupPage` (Paramètres) ET l'onboarding
/// (1re ouverture — pour récupérer sa config sans tout re-saisir).
///
/// Étapes : sélection fichier → mot de passe → lecture/décrypt → confirmation
/// (résumé + avertissement écrasement) → application.
/// Retourne `true` si une sauvegarde a effectivement été appliquée.
Future<bool> runBackupImportFlow(BuildContext context) async {
  // 1. Sélection du fichier.
  //
  // Revue 2026-09-11, D4B-14 — Sur une box sans application de sélection de
  // documents, le sélecteur LÈVE (erreur de plateforme) : rien ne l'attrapait,
  // « Importer » ne faisait rien et le bouton revenait sans un mot — sur le
  // chemin de restauration de l'onboarding, le plus exposé.
  final ScaffoldMessengerState? pickMessenger =
      ScaffoldMessenger.maybeOf(context);
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
  } catch (e) {
    debugPrint('❌ §restore — sélecteur de fichiers indisponible : $e');
    pickMessenger?.showSnackBar(SnackBar(
        content: Text(L10n.current.commonFailedWith(describeError(e)))));
    return false;
  }
  if (picked == null || picked.files.single.path == null) return false;
  final path = picked.files.single.path!;
  if (!context.mounted) return false;

  // 2. Saisie du mot de passe.
  final password = await _askImportPassword(context);
  if (password == null || password.isEmpty) return false;
  if (!context.mounted) return false;

  // 3. Lecture + décrypt en mémoire (sans appliquer).
  final messenger = ScaffoldMessenger.of(context);
  BackupContent content;
  try {
    content = await BackupService.readBackup(path, password);
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('❌ ${describeError(e)}')));
    return false;
  }
  if (!context.mounted) return false;

  // 4. Confirmation avec résumé.
  final ok = await _confirmApply(context, content);
  if (ok != true || !context.mounted) return false;

  // 5. Application effective.
  try {
    await BackupService.applyBackup(content);
    // §restoreTrace — Journalisé : c'est ici que se joue « pourquoi l'app
    // repart-elle sur l'onboarding après une restauration ». Si le contexte
    // n'est plus monté, le dialogue de succès est sauté SANS que rien ne le
    // dise, et l'appelant enchaîne aussitôt sur sa propre navigation.
    debugPrint('🚦 §restoreTrace — backup appliqué · '
        'contexte monté = ${context.mounted}');
    if (context.mounted) await _showImportSuccessDialog(context, content);
    debugPrint('🚦 §restoreTrace — flux de restauration terminé (true)');
    return true;
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(
          content: Text(L10n.current.commonFailedWith(describeError(e)))));
    }
    return false;
  }
}

Future<String?> _askImportPassword(BuildContext context) async {
  final ctrl = TextEditingController();
  return showAppDialog<String>(
    context: context,
    builder: (ctx) {
      bool visible = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ctx.l10n.bkRestorePasswordTitle),
          content: TextField(
            controller: ctrl,
            obscureText: !visible,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: ctx.l10n.bkPasswordLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setLocal(() => visible = !visible),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(ctx.l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              // D4B-08 — le texte suit le fond (noir OU blanc, cf. `onColorFor`) :
              // un accent assombri pour le thème clair rendait le noir illisible.
              style: FilledButton.styleFrom(
                backgroundColor: kAccentPrimary,
                foregroundColor: onColorFor(kAccentPrimary),
              ),
              child: Text(ctx.l10n.bkDecrypt),
            ),
          ],
        ),
      );
    },
  ).whenComplete(() {
    // §tourFix — Le mot de passe de la sauvegarde ne doit pas survivre au
    // dialogue : on l'efface TOUT DE SUITE (c'est l'objectif de sécurité, et
    // c'est déterministe). Le `dispose`, lui, attend la frame suivante : la
    // fenêtre est encore montée pendant sa transition de sortie et touche
    // encore au controller (`clearComposing()` à la perte de focus) — le
    // disposer dans la foulée déclenche « used after being disposed ».
    ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  });
}

Future<bool?> _confirmApply(BuildContext context, BackupContent content) async {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // ⚠️ `Expanded` obligatoire : sans lui le titre déborde (« RIGHT
      // OVERFLOWED BY 12 PIXELS » constaté sur Galaxy S25, 2026-09-04) — le
      // `Row` d'un titre d'`AlertDialog` est contraint par la largeur du
      // dialogue, et un `Text` non flexible ne se coupe pas.
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: kWarning, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(ctx.l10n.bkConfirmRestoreTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Revue 2026-09-11, D4B-05 — était écrit en dur, en français.
            ctx.l10n.bkBackupFrom(
                _fmtDate(content.exportedAt), content.appVersion),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kAccentPrimary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kAccentPrimary.withAlpha(80), width: 1),
            ),
            child: Text(
              content.summary(),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kAccentPrimary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ctx.l10n.bkConfirmRestoreBody,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          // §safeFocus — Restauration (tout est ÉCRASÉ) : le focus d'entrée va
          // sur « Annuler », sur TV OK est le geste réflexe.
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: kWarning,
            foregroundColor: onColorFor(kWarning), // D4B-08
          ),
          child: Text(ctx.l10n.bkRestore),
        ),
      ],
    ),
  );
}

Future<void> _showImportSuccessDialog(
    BuildContext context, BackupContent content) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: kAccentPrimary, size: 22),
          const SizedBox(width: 8),
          // Même garde que le dialogue de confirmation ci-dessus.
          Expanded(child: Text(ctx.l10n.bkRestoreDone)),
        ],
      ),
      content: Text(
        '${content.summary()}\n\n${ctx.l10n.bkRestoreDoneSub}',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: kAccentPrimary,
            foregroundColor: onColorFor(kAccentPrimary), // D4B-08
          ),
          child: Text(ctx.l10n.commonOk),
        ),
      ],
    ),
  );
}

String _fmtDate(DateTime d) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}h${pad(d.minute)}';
}
