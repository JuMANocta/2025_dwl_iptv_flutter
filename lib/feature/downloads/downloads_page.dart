import 'package:flutter/material.dart';
import 'widgets/download_task_tile.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: _downloadManager.tasksNotifier,
        builder: (context, tasks, child) {
          // §12-a — Empty state unifié : conservé pour la liste TOTALEMENT
          // vide (aucun téléchargement n'a jamais été lancé). Un filtre qui ne
          // ramène rien a son propre message, plus contextuel.
          if (tasks.isEmpty) {
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

          return Column(
            children: [
              _buildFilters(tasks),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.55,
                              child: Center(
                                child: Text(
                                  _searchCtrl.text.trim().isNotEmpty
                                      ? 'Aucun téléchargement ne correspond à cette recherche.'
                                      : 'Aucun téléchargement dans « ${_filter.label} ».',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visible.length,
                          itemBuilder: (context, index) =>
                              DownloadTaskTile(task: visible[index]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
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
