import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'widgets/download_task_tile.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/device_library_service.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';

/// §dlTheme — Puce de filtre reprenant le langage visuel des puces de l'app
/// (cf. les chips de saison de `DetailsPage`) : teinte de l'accent en fond,
/// bordure plus marquée à la sélection. Un `ChoiceChip` Material brut ne suivait
/// pas le thème et détonnait dès qu'on changeait de preset.
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FocusableChip(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Ink(
            // §touchTarget — 7 dp de rembourrage vertical donnaient un chip de
            // ~30 dp. Le texte n'a pas changé, la cible passe à 48.
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? color.withAlpha(55) : color.withAlpha(20),
              border: Border.all(
                color: selected ? color.withAlpha(200) : color.withAlpha(60),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? color : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: selected ? color : cs.onSurfaceVariant.withAlpha(160),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §dlErgo — Filtres de la page Téléchargements.
enum DownloadFilter { all, active, completed, errors }

extension on DownloadFilter {
  String get label => switch (this) {
        DownloadFilter.all => 'Tout',
        DownloadFilter.active => 'En cours',
        DownloadFilter.completed => 'Terminés',
        DownloadFilter.errors => 'Erreurs',
      };

  /// `active` regroupe tout ce qui est en mouvement (y compris la finalisation,
  /// qui n'est ni terminée ni en erreur) ; `errors` regroupe échecs ET
  /// annulations — deux états qui appellent la même réaction : relancer.
  bool matches(DownloadStatus s) => switch (this) {
        DownloadFilter.all => true,
        DownloadFilter.active => s == DownloadStatus.downloading ||
            s == DownloadStatus.queued ||
            s == DownloadStatus.paused ||
            s == DownloadStatus.finalizing,
        DownloadFilter.completed => s == DownloadStatus.completed,
        DownloadFilter.errors =>
          s == DownloadStatus.failed || s == DownloadStatus.canceled,
      };
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> with TvInitialFocus {
  final DownloadManagerService _downloadManager = DownloadManagerService();

  DownloadFilter _filter = DownloadFilter.all;
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  /// §12-c — Pull-to-refresh : recharge les tâches depuis disque + réconcilie
  /// les statuts (utile si une tâche s'est figée en `downloading` après crash).
  Future<void> _refresh() => _downloadManager.init();

  /// §dlOrphans — Le balayage MANUEL du dossier public (bouton ⟳ de la barre).
  /// Jamais muet : le résultat s'annonce, même quand il n'y a rien.
  Future<void> _scanDevice() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await DeviceLibraryService.scan(_downloadManager.tasksNotifier.value);
    if (!mounted) return;
    final String text = result.permissionDenied
        ? l10n.dlScanDenied
        : result.orphans.isEmpty
            ? l10n.dlScanNothing
            : l10n.dlScanFound(
                result.orphans.length, formatFileSize(result.totalBytes));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _searchCtrl.clear();
    });
  }

  List<DownloadTask> _apply(List<DownloadTask> tasks) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return tasks.where((t) {
      if (!_filter.matches(t.status)) return false;
      if (q.isEmpty) return true;
      return t.displayName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Rechercher un téléchargement',
                  border: InputBorder.none,
                ),
              )
            : Text(l10n.downloadManagerTitle),
        actions: [
          // §dlOrphans — Le balayage du dossier public est MANUEL (décision
          // utilisateur) : ce bouton, et rien d'automatique.
          ValueListenableBuilder<bool>(
            valueListenable: DeviceLibraryService.scanning,
            builder: (context, scanning, _) => IconButton(
              icon: scanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined),
              tooltip: l10n.dlScanTooltip,
              onPressed: scanning ? null : _scanDevice,
            ),
          ),
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: _downloadManager.tasksNotifier,
        builder: (context, tasks, child) =>
            ValueListenableBuilder<List<DeviceVideo>>(
          valueListenable: DeviceLibraryService.videos,
          builder: (context, orphans, _) => _buildBody(context, tasks, orphans),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<DownloadTask> tasks,
    List<DeviceVideo> orphans,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // §12-a — Empty state unifié : conservé pour la liste TOTALEMENT vide
    // (aucun téléchargement n'a jamais été lancé, et rien sur l'appareil). Un
    // filtre qui ne ramène rien a son propre message, plus contextuel.
    if (tasks.isEmpty && orphans.isEmpty) {
      // Le RefreshIndicator a besoin d'un Scrollable pour fonctionner,
      // donc on emballe l'empty state dans une ListView qui prend toute
      // la hauteur disponible.
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: EmptyState(
                icon: Icons.download_done,
                title: l10n.noDownloads,
                subtitle:
                    'Lance un téléchargement depuis la fiche d\'un film ou d\'une série — il apparaîtra ici avec sa progression.',
              ),
            ),
          ],
        ),
      );
    }

    final visible = _apply(tasks);
    // §dlOrphans — La section « Sur l'appareil » vit en TÊTE de la liste
    // (c'est là qu'on la cherche), et ne dépend pas du filtre : ce ne sont
    // pas des tâches.
    final orphanSection =
        orphans.isEmpty ? null : _OnDeviceSection(videos: orphans);

    return Column(
      children: [
        if (tasks.isNotEmpty) _buildFilters(tasks),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: (orphanSection == null ? 0 : 1) +
                  (visible.isEmpty && tasks.isNotEmpty ? 1 : visible.length),
              itemBuilder: (context, index) {
                var i = index;
                if (orphanSection != null) {
                  if (i == 0) return orphanSection;
                  i--;
                }
                if (visible.isEmpty) {
                  return SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Text(
                        _searchCtrl.text.trim().isNotEmpty
                            ? 'Aucun téléchargement ne correspond à cette recherche.'
                            : 'Aucun téléchargement dans « ${_filter.label} ».',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return DownloadTaskTile(task: visible[i]);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Puces de filtre avec compteur : « Erreurs 2 » se repère d'un coup d'œil,
  /// sans scroller toute la liste.
  Widget _buildFilters(List<DownloadTask> tasks) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in DownloadFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: _FilterChip(
                  label: f.label,
                  count: tasks.where((t) => f.matches(t.status)).length,
                  selected: _filter == f,
                  // Les erreurs se repèrent à leur couleur, comme partout
                  // ailleurs dans l'app.
                  color: f == DownloadFilter.errors ? kError : kAccentPrimary,
                  onTap: () => setState(() => _filter = f),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// §dlOrphans — La section « Sur l'appareil » : les fichiers du dossier public
/// que la liste ne connaît pas, lisibles et supprimables un par un.
///
/// ⚠️ §dpadChildFocus : le bouton Supprimer est un FRÈRE de la carte, jamais
/// son enfant — un rect contenu dans la carte n'est candidat au focus dans
/// aucune direction.
class _OnDeviceSection extends StatelessWidget {
  const _OnDeviceSection({required this.videos});

  final List<DeviceVideo> videos;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final int total = videos.fold<int>(0, (a, v) => a + v.size);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.sd_storage_outlined, size: 18, color: kAccentSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dlOnDeviceTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                    ),
                    Text(
                      l10n.dlOnDeviceSub(videos.length, formatFileSize(total)),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final v in videos) _OnDeviceTile(video: v),
        const Divider(height: 24),
      ],
    );
  }
}

class _OnDeviceTile extends StatelessWidget {
  const _OnDeviceTile({required this.video});

  final DeviceVideo video;

  void _play(BuildContext context) {
    // Même chemin que `DownloadTaskTile._openFile` : lecture du fichier
    // local. La clé de progression est le chemin (aucune URL réseau connue
    // pour un orphelin).
    final progress = WatchProgressService.getProgress(video.path);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          path: video.path,
          title: video.title,
          sourceType: VideoSourceType.file,
          progressKey: video.path,
          startPosition: progress?.position,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final bool ok = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.dlOrphanDeleteTitle),
            content: Text(
              l10n.dlOrphanDeleteBody(video.title, formatFileSize(video.size)),
            ),
            actions: [
              TextButton(
                // §safeFocus — à la télécommande, OK est le geste réflexe :
                // il tombe sur le bouton sûr.
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.commonDelete, style: TextStyle(color: kError)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final deleted = await DeviceLibraryService.delete(video);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(deleted ? l10n.dlOrphanDeleted : l10n.dlOrphanDeleteFailed),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final String date = DateFormat('dd/MM/yyyy').format(video.modifiedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: FocusableCard(
              decorateOnly: true,
              scaleOnFocus: false,
              onTap: () => _play(context),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(Icons.movie_outlined, color: kAccentSecondary),
                title: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatFileSize(video.size)} · $date',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                trailing: Icon(Icons.play_arrow_rounded, color: kAccentPrimary),
                onTap: () => _play(context),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            icon: Icon(Icons.delete_outline, color: kError),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }
}
