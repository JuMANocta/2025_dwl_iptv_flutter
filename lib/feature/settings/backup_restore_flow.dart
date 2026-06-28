import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/services/backup_service.dart';

/// Flux UI complet de restauration d'une sauvegarde `.aether` (§10), extrait
/// pour être réutilisable depuis `BackupPage` (Paramètres) ET l'onboarding
/// (1re ouverture — pour récupérer sa config sans tout re-saisir).
///
/// Étapes : sélection fichier → mot de passe → lecture/décrypt → confirmation
/// (résumé + avertissement écrasement) → application.
/// Retourne `true` si une sauvegarde a effectivement été appliquée.
Future<bool> runBackupImportFlow(BuildContext context) async {
  // 1. Sélection du fichier.
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.any,
    allowMultiple: false,
  );
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
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    return false;
  }
  if (!context.mounted) return false;

  // 4. Confirmation avec résumé.
  final ok = await _confirmApply(context, content);
  if (ok != true || !context.mounted) return false;

  // 5. Application effective.
  try {
    await BackupService.applyBackup(content);
    if (context.mounted) await _showImportSuccessDialog(context, content);
    return true;
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('❌ Échec : $e')));
    return false;
  }
}

Future<String?> _askImportPassword(BuildContext context) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      bool visible = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mot de passe de la sauvegarde'),
          content: TextField(
            controller: ctrl,
            obscureText: !visible,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
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
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              style: FilledButton.styleFrom(
                backgroundColor: kAccentPrimary,
                foregroundColor: Colors.black,
              ),
              child: const Text('Déchiffrer'),
            ),
          ],
        ),
      );
    },
  );
}

Future<bool?> _confirmApply(BuildContext context, BackupContent content) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: kWarning, size: 22),
          const SizedBox(width: 8),
          const Text('Confirmer la restauration'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sauvegarde du ${_fmtDate(content.exportedAt)} '
            '(v${content.appVersion}) :',
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
            'Tout l\'état actuel (comptes, clé TMDB, thème, favoris, '
            'progression de lecture) sera ÉCRASÉ par cette sauvegarde.\n\n'
            'Action irréversible. Continuer ?',
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
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: kWarning,
            foregroundColor: Colors.black,
          ),
          child: const Text('Restaurer'),
        ),
      ],
    ),
  );
}

Future<void> _showImportSuccessDialog(
    BuildContext context, BackupContent content) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: kAccentPrimary, size: 22),
          const SizedBox(width: 8),
          const Text('Restauration réussie'),
        ],
      ),
      content: Text(
        '${content.summary()}\n\n'
        'Les playlists IPTV seront re-téléchargées au prochain démarrage.',
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
            foregroundColor: Colors.black,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String _fmtDate(DateTime d) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}h${pad(d.minute)}';
}
