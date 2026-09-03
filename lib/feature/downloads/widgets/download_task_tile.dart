import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/main.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/downloads/logic/download_tile_actions.dart';
import 'package:aetherStream/widgets/info_row.dart';
import 'package:aetherStream/widgets/terminal_download_dialog.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:media_store_plus/media_store_plus.dart';

class DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;

  const DownloadTaskTile({super.key, required this.task});

  /// §dlErgo — Exécute une action de la table [downloadTileActions].
  ///
  /// Le tap de la tuile n'appelle plus que l'action PRINCIPALE, garantie non
  /// destructive : avant, taper un téléchargement en cours l'annulait sans
  /// confirmation (et sur TV c'était la touche OK).
  Future<void> _run(BuildContext context, DownloadAction action) async {
    final downloadManager = DownloadManagerService();
    switch (action) {
      case DownloadAction.play:
        _openFile(context);

      case DownloadAction.monitor:
        _openMonitor();

      case DownloadAction.restart:
        debugPrint("🔄 Relance du téléchargement : ${task.displayName}");
        // `restartTask` coupe le transfert en cours ET attend sa fin réelle
        // avant de reprendre (sinon deux handles écriraient dans le même
        // fichier partiel). Progression conservée via la reprise `Range`.
        // Arrière-plan intentionnel : les erreurs sont gérées dans le service.
        unawaited(downloadManager.restartTask(task));
        _openMonitor(isResume: true);

      case DownloadAction.cancel:
        if (!context.mounted) return;
        final confirmed = await _confirmCancel(context);
        if (confirmed) await downloadManager.cancelTask(task.id);

      case DownloadAction.delete:
        if (context.mounted) await _deleteTask(context);
    }
  }

  /// Ouvre le moniteur depuis le navigator racine (la tuile peut vivre dans un
  /// onglet, le dialogue doit couvrir toute l'app).
  void _openMonitor({bool isResume = false}) {
    final rootContext = navigatorKey.currentContext;
    if (rootContext == null || !rootContext.mounted) return;
    showAppDialog(
      context: rootContext,
      builder: (_) =>
          TerminalDownloadDialog(taskId: task.id, isResume: isResume),
    );
  }

  /// §dlErgo — L'annulation était la seule action destructive SANS garde-fou
  /// (la suppression, elle, en avait déjà une).
  Future<bool> _confirmCancel(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.stop_circle_outlined, color: kWarning),
            const SizedBox(width: 12),
            const Expanded(child: Text('Arrêter le téléchargement ?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.displayName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ce qui est déjà téléchargé est conservé : tu pourras reprendre '
              'là où ça s\'est arrêté.',
            ),
          ],
        ),
        actions: [
          TextButton(
            // §safeFocus — Le focus d'entrée va sur « Annuler » : sur TV, OK
            // est le geste réflexe, il ne doit pas arrêter le transfert.
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kWarning,
              foregroundColor: kBlack,
            ),
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Arrêter'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// §dlErgo — Menu ⋯ : toutes les actions secondaires, dont les destructives.
  Future<void> _openMenu(BuildContext context) async {
    final actions = downloadTileActions(task.status).menu;
    if (actions.isEmpty) return;
    final choice = await showAdaptiveActionSheet<DownloadAction>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                autofocus: a == actions.first,
                leading: Icon(_actionIcon(a),
                    color: a.isDestructive ? kError : null),
                title: Text(
                  _actionLabel(a),
                  style: TextStyle(color: a.isDestructive ? kError : null),
                ),
                onTap: () => Navigator.of(sheetCtx).pop(a),
              ),
          ],
        ),
      ),
    );
    if (choice != null && context.mounted) await _run(context, choice);
  }

  /// §dlErgo — Action de relance disponible pour ce statut, s'il y en a une.
  /// Sortie du menu ⋯ pour être visible directement sur la tuile.
  ///
  /// `null` sur un téléchargement TERMINÉ : il n'y a plus de fichier partiel à
  /// reprendre, relancer repartirait de zéro.
  ///
  /// §dlWatchdog — `null` aussi pendant le TRANSFERT : le service reconnecte
  /// désormais de lui-même quand le débit décroche. Le bouton demandait à
  /// l'utilisateur de surveiller un chiffre et d'appuyer au bon moment ; le
  /// compteur « relancé ×N » lui dit maintenant ce qui s'est passé. Il reste
  /// visible sur `queued`/`paused`, où il veut dire « démarre maintenant ».
  DownloadAction? get _restartAction {
    if (task.status == DownloadStatus.downloading) return null;
    final a = downloadTileActions(task.status);
    if (a.primary == DownloadAction.restart) return null; // déjà sur le tap
    return a.menu.contains(DownloadAction.restart)
        ? DownloadAction.restart
        : null;
  }

  /// Bouton d'action bordé : sans contour, deux `IconButton` côte à côte se
  /// lisaient comme un seul élément.
  Widget _outlinedAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withAlpha(120)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }

  static IconData _actionIcon(DownloadAction a) => switch (a) {
        DownloadAction.play => Icons.play_arrow_rounded,
        DownloadAction.monitor => Icons.terminal,
        DownloadAction.restart => Icons.refresh,
        DownloadAction.cancel => Icons.stop_circle_outlined,
        DownloadAction.delete => Icons.delete_forever_outlined,
      };

  static String _actionLabel(DownloadAction a) => switch (a) {
        DownloadAction.play => 'Lire',
        DownloadAction.monitor => 'Voir la progression',
        DownloadAction.restart => 'Relancer',
        DownloadAction.cancel => 'Arrêter le téléchargement',
        DownloadAction.delete => 'Supprimer',
      };

  Future<void> _deleteTask(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final downloadManager = DownloadManagerService();
    final bool? confirm = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // 1. Un titre avec une icône d'avertissement claire
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: kWarning),
            const SizedBox(width: 12),
            Text(l10n.deleteDialogTitle),
          ],
        ),

        // 2. Un contenu structuré qui donne confiance
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On met en évidence le nom du fichier concerné
            Text(
              task.displayName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // On ajoute la taille pour être sûr de ce qu'on supprime
            InfoRow(
                icon: Icons.straighten,
                label: l10n.deleteDialogSizeLabel,
                value: formatFileSize(task.totalSize)
            ),
            const Divider(height: 24),
            // Un message d'avertissement plus explicite
            Text(l10n.deleteDialogWarning),
          ],
        ),

        // 3. Des boutons d'action sans ambiguïté
        actions: [
          TextButton(
            // §safeFocus — Suppression : le focus d'entrée va sur « Annuler »
            // (sur TV, OK est le geste réflexe).
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            // On donne au bouton un style "destructif"
            style: FilledButton.styleFrom(
              backgroundColor: kError,
              foregroundColor: kWhite, // Pour que le texte et l'icône soient blancs
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text(l10n.deleteDialogConfirmButton),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await downloadManager.removeTask(task.id);

      // §dlDirectWrite — Le fichier final est désormais écrit DIRECTEMENT dans
      // le dossier public : on l'efface par son chemin. MediaStore reste
      // ensuite appelé sur Android pour purger l'entrée d'index.
      try {
        final finalFile = File(task.finalPath);
        if (await finalFile.exists()) await finalFile.delete();
      } catch (e) {
        debugPrint("⚠️ Suppression du fichier final échouée : $e");
      }

      if (Platform.isAndroid) {
        // Suppression du fichier final via MediaStore (Android 10+)
        try {
          final fileName = task.finalPath.split('/').last;
          if (fileName.isNotEmpty) {
            await MediaStore().deleteFile(
              fileName: fileName,
              dirType: DirType.video,
              dirName: DirName.movies,
            );
          }
        } catch (e) {
          debugPrint("⚠️ Suppression MediaStore échouée : $e");
        }
      }

      // Suppression du fichier partiel (`.<nom>.part` à côté du final, ou
      // résidu dans le cache privé quand le repli a servi).
      try {
        final tempFile = File(task.tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) {
        debugPrint("⚠️ Suppression fichier partiel échouée : $e");
      }
    }
  }

  Future<void> _openFile(BuildContext context) async {
    // §forgetResume — On joue le fichier LOCAL mais on garde l'URL réseau
    // comme clé de progression. Effet : la lecture du fichier téléchargé
    // continue à alimenter la pile "Reprendre" de la home (qui regarde par
    // `entry.url`), et la reprise depuis la home reste cohérente même si le
    // film a été regardé partiellement en local.
    final progress = WatchProgressService.getProgress(task.url);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(
          path: task.finalPath,
          title: task.displayName,
          sourceType: VideoSourceType.file,
          progressKey: task.url,
          startPosition: progress?.position,
        ),
      ),
    );
  }

  // --- WIDGETS D'UI ---
  Widget _getLeadingIcon(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (task.status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            // On s'assure que les deux indicateurs sont parfaitement centrés l'un sur l'autre
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: null, // Mode indéterminé (rotation continue)
                strokeWidth: 2, // Un peu plus fin pour être discret
                color: cs.surfaceContainerHighest,
              ),
              CircularProgressIndicator(
                value: task.progress, // Mode déterministe (remplissage)
                strokeWidth: 3, // Un peu plus épais pour être au premier plan
                color: kSuccess,
                backgroundColor: Colors.transparent, // Fond transparent pour voir celui du dessous
              ),
            ],
          ),
        );
      case DownloadStatus.completed:
        return Icon(Icons.check_circle, color: kSuccess);
      case DownloadStatus.failed:
        return Icon(Icons.error, color: kError);
      case DownloadStatus.canceled:
        return Icon(Icons.cancel, color: kWarning);
      case DownloadStatus.paused:
        // §dlTheme — était `Colors.blueGrey` : une couleur hors palette, qui
        // ne bougeait pas d'un preset à l'autre.
        return Icon(Icons.pause_circle, color: cs.onSurfaceVariant);
      case DownloadStatus.queued:
        return Icon(Icons.hourglass_top, color: cs.onSurfaceVariant);
      case DownloadStatus.finalizing:
        return Icon(Icons.check_circle, color: kSuccess);
    }
  }

  /// §dlWatchdog — Sous-titre = état du transfert, précédé du nombre de
  /// relances quand il y en a eu.
  ///
  /// Le compteur ne vivait que dans le moniteur terminal, donc il disparaissait
  /// dès qu'on le refermait : rien ne disait plus qu'un fichier avait déjà
  /// décroché cinq fois. C'est pourtant le signal qui distingue « lent » de
  /// « source qui bride ».
  Widget _buildSubtitle(BuildContext context) {
    final status = _buildStatusLine(context);
    if (task.retryCount == 0) return status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 12, color: kWarning),
              const SizedBox(width: 3),
              Text(
                'relancé ×${task.retryCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: kWarning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        status,
      ],
    );
  }

  Widget _buildStatusLine(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(task.createdAt);
    switch (task.status) {
      case DownloadStatus.downloading:
        String remainingText = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final remainingBytes = task.totalSize * (1 - task.progress);
          remainingText = l10n.taskStatusRemaining(formatFileSize(remainingBytes.toInt()));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "${l10n.taskStatusDownloading}$remainingText",
              style: const TextStyle(fontSize: 12)
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: task.progress, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, color: kSuccess),
        ]);
      case DownloadStatus.completed:
        return Text(
            l10n.taskStatusCompleted(formatFileSize(task.totalSize), formattedDate),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)
        );
      case DownloadStatus.failed:
        final String errorText = task.errorMessage ?? l10n.taskStatusUnknownError;
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = ' ($percentage% - $downloadedSize / $totalSize)';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.taskStatusFailed(progressInfo),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold, // On met en évidence l'échec
              ),
            ),
            Text(
              errorText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.9),
              ),
            ),
          ],
        );
      case DownloadStatus.canceled:
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = '($percentage% - $downloadedSize / $totalSize)';
        }
        return Text(
            l10n.taskStatusCanceled(progressInfo),
            style: TextStyle(fontSize: 12, color: kWarning)
        );
      case DownloadStatus.finalizing:
        return Text(
          "${l10n.terminalFinalizingMessage.trim()}...",
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
      default:
        return Text(
          l10n.taskStatusPending(formattedDate),
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Construire le titre avec l'année si disponible
    String titleText = task.displayName;
    if (task.releaseYear != null && task.releaseYear!.isNotEmpty) {
      titleText = '$titleText (${task.releaseYear})';
    }

    // §dlErgo — Le tap ne déclenche plus que l'action PRINCIPALE (jamais
    // destructive) ; tout le reste passe par le menu ⋯.
    final primary = downloadTileActions(task.status).primary;
    // §3c-3 → §dpadChildFocus — La tuile et ses actions sont des focusables
    // FRÈRES dans une `Row`, à rectangles disjoints (même motif que les cartes
    // de comptes). Avant, Relancer et ⋯ étaient le `trailing` du `ListTile`,
    // DANS la `FocusableCard` : depuis dpad 3.0, `DpadFocusable` enveloppe son
    // enfant d'un `ExcludeFocus`, donc arrêter / supprimer un téléchargement
    // était impossible à la télécommande. `excludeChildFocus: false` n'y
    // changerait rien (un rect CONTENU dans la carte n'est candidat dans
    // aucune direction pour la politique de traversée).
    //
    // Les actions portent un CONTOUR (§dlErgo) : sans lui, l'œil ne repérait
    // qu'un seul bouton et « Relancer » restait introuvable. Relancer est sorti
    // du menu ⋯ : c'est l'action qu'on cherche quand le débit s'effondre, elle
    // doit être atteignable en un geste. Le bouton garde son `onPressed` pour
    // le tactile ; au D-pad c'est la chip qui prend le focus et relaie OK.
    return Row(
      children: [
        Expanded(
          // decorateOnly = on garde le ListTile et son tap mobile/souris ; sur
          // TV, la touche OK télécommande déclenche la même action principale.
          child: FocusableCard(
            decorateOnly: true,
            // §tvErgo — tuile pleine largeur : pas de scale (sinon débordement
            // écran).
            scaleOnFocus: false,
            onTap: () => _run(context, primary),
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              leading: _getLeadingIcon(context),
              title: Text(titleText,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: _buildSubtitle(context),
              onTap: () => _run(context, primary),
              isThreeLine: task.status == DownloadStatus.downloading,
            ),
          ),
        ),
        if (_restartAction != null) ...[
          FocusableChip(
            onTap: () => _run(context, _restartAction!),
            borderRadius: BorderRadius.circular(10),
            child: _outlinedAction(
              context,
              icon: Icons.refresh,
              tooltip: _actionLabel(_restartAction!),
              color: kAccentSecondary,
              onPressed: () => _run(context, _restartAction!),
            ),
          ),
          const SizedBox(width: 8),
        ],
        FocusableChip(
          onTap: () => _openMenu(context),
          borderRadius: BorderRadius.circular(10),
          child: _outlinedAction(
            context,
            icon: Icons.more_vert,
            tooltip: 'Autres actions',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: () => _openMenu(context),
          ),
        ),
        // Aligné sur le `contentPadding` horizontal du ListTile.
        const SizedBox(width: 16),
      ],
    );
  }
}
