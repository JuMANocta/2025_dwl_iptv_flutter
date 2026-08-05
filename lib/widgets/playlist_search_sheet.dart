import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../data/models/m3u_entry.dart';
import '../data/services/parsed_playlist_service.dart';
import '../feature/search/m3u_filter.dart';
import 'tv/tv_adaptive_modal.dart';

/// §tmdbOnlyDetails — Recherche MANUELLE d'un titre dans les listes.
///
/// Sert de porte de sortie à la fiche d'un titre absent : le repérage
/// automatique (`ActorDetailsPage._findMatches`) est **volontairement exact**
/// pour ne jamais produire de faux positif, donc il rate les titres présents
/// sous une graphie différente. Plutôt que d'assouplir ce matching en douce —
/// ce qui reviendrait sur une décision délibérée — on laisse l'utilisateur
/// chercher lui-même et trancher.
///
/// La feuille est pré-remplie avec le titre localisé et propose une bascule
/// vers le titre original : les fournisseurs IPTV nomment souvent en VO.
class PlaylistSearchSheet extends StatefulWidget {
  /// Titre localisé (pré-rempli).
  final String title;

  /// Titre original TMDB, si différent → bouton de bascule.
  final String? originalTitle;

  /// Restreint la recherche au même type que le titre consulté.
  final M3uContentType type;

  const PlaylistSearchSheet({
    super.key,
    required this.title,
    this.originalTitle,
    required this.type,
  });

  /// Ouvre la feuille et retourne le groupe choisi (toutes les versions du
  /// titre), ou `null` si l'utilisateur ferme sans choisir.
  static Future<List<M3uEntry>?> show(
    BuildContext context, {
    required String title,
    String? originalTitle,
    required M3uContentType type,
  }) {
    return showAdaptiveActionSheet<List<M3uEntry>>(
      context: context,
      scrollable: false, // la liste de résultats gère son propre scroll
      builder: (_) => PlaylistSearchSheet(
        title: title,
        originalTitle: originalTitle,
        type: type,
      ),
    );
  }

  @override
  State<PlaylistSearchSheet> createState() => _PlaylistSearchSheetState();
}

class _PlaylistSearchSheetState extends State<PlaylistSearchSheet> {
  late final TextEditingController _ctrl;
  List<List<M3uEntry>> _groups = const [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.title);
    _search(widget.title);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Même prédicat que la recherche de l'accueil (`_SearchView._filterAndGroup`)
  /// : `contains` sur le nom affiché ET sur le titre brut, puis regroupement par
  /// `contentGroupKey` (la clé de fusion cross-listes de l'app).
  void _search(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      setState(() => _groups = const []);
      return;
    }

    final byGroup = <String, List<M3uEntry>>{};
    for (final e in ParsedPlaylistService.entries) {
      if (e.type != widget.type) continue;
      if (!e.displayName.toLowerCase().contains(q) &&
          !e.rawTitle.toLowerCase().contains(q)) {
        continue;
      }
      final key = widget.type == M3uContentType.tv
          ? tvGroupKey(e.displayName)
          : contentGroupKey(e);
      byGroup.putIfAbsent(key, () => []).add(e);
    }

    if (widget.type == M3uContentType.tv) {
      for (final k in byGroup.keys.toList()) {
        byGroup[k] = dedupeTvVersions(byGroup[k]!);
      }
    }

    final groups = byGroup.values.toList();
    if (groups.length > 40) groups.length = 40;
    setState(() => _groups = groups);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final original = widget.originalTitle;
    final showOriginalToggle =
        original != null && original.trim().isNotEmpty && original != widget.title;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chercher dans mes listes',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintText: 'Titre à chercher',
            ),
          ),
          if (showOriginalToggle) ...[
            const SizedBox(height: 8),
            // Les providers IPTV nomment très souvent en VO : c'est déjà la
            // 2e passe du repérage automatique, on l'expose ici en un tap.
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.translate, size: 16),
                label: Text('Titre original : $original'),
                onPressed: () {
                  _ctrl.text = original;
                  _ctrl.selection =
                      TextSelection.collapsed(offset: original.length);
                  _search(original);
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: _groups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        _ctrl.text.trim().length < 2
                            ? 'Saisis au moins 2 caractères.'
                            : 'Aucun titre trouvé dans vos listes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _groups.length,
                    itemBuilder: (_, i) {
                      final group = _groups[i];
                      final first = group.first;
                      final year = first.title.year;
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.movie_outlined, color: kAccentPrimary),
                        title: Text(
                          first.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (year != null) year,
                            '${group.length} version${group.length > 1 ? 's' : ''}',
                          ].join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        onTap: () => Navigator.of(context).pop(group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
