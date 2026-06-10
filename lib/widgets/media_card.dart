import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/widgets/media_chips.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';

// ─── Poster partagé ──────────────────────────────────────────────────────────

Widget _poster(List<M3uEntry> versions, IconData fallbackIcon, Color accentColor) {
  // §23 — image de la version du compte le plus riche (politique « plus
  // grosse liste »), fallback par taille décroissante.
  final logoUrl = ParsedPlaylistService.bestLogoUrl(versions);
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 70, height: 105,
      child: logoUrl != null && logoUrl.isNotEmpty
          ? Image.network(
              logoUrl,
              width: 70, height: 105, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _posterFallback(fallbackIcon, accentColor),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _posterFallback(fallbackIcon, accentColor),
            )
          : _posterFallback(fallbackIcon, accentColor),
    ),
  );
}

Widget _posterFallback(IconData icon, Color color) {
  return Container(
    color: color.withAlpha(20),
    child: Center(child: Icon(icon, color: color.withAlpha(120), size: 32)),
  );
}

// ─── Badge catégorie ─────────────────────────────────────────────────────────

Widget _categoryBadge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withAlpha(100)),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

// ─── Conteneur de carte ───────────────────────────────────────────────────────

Widget _cardShell({
  required BuildContext context,
  required Widget child,
  required VoidCallback onTap,
  required Gradient accentGradient,
}) {
  final cs = Theme.of(context).colorScheme;
  // §3c-3 — FocusableCard remplace Material+InkWell+ClipRRect : sur Android TV
  // l'élément gagne un focus visible (bordure + glow + scale 1.05) au D-pad ;
  // sur mobile, comportement neutre (juste un InkWell). Le splash custom
  // kAccentPrimary disparaît (les ripples Material par défaut suffisent).
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: FocusableCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      backgroundColor: cs.surfaceContainer,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barre accent gauche (3 px, gradient de l'app)
            Container(width: 3, decoration: BoxDecoration(gradient: accentGradient)),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

// ─── FilmCard ────────────────────────────────────────────────────────────────

class FilmCard extends StatelessWidget {
  final String filmKey;
  final List<M3uEntry> versions;
  final void Function(List<M3uEntry>) onTap;

  const FilmCard({super.key, required this.filmKey, required this.versions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs             = Theme.of(context).colorScheme;
    final displayTitle   = filmKey;
    // Catégorie calculée depuis la liste des versions (compte prioritaire en premier)
    final categoryLabel  = versions.isNotEmpty
        ? contentCategoryLabel(versions.first.groupTitle)
        : null;
    final uniqueYears       = versions.map((v) => v.title.year).where((y) => y != null).toSet();
    final isHomonymConflict = versions.length > 1 && uniqueYears.length > 1;
    // Dédupliquer par valeur (label) et non par identité Widget
    final uniqueChips = uniqueChipsForVersions(versions);

    return _cardShell(
      context: context,
      onTap: () => onTap(versions),
      accentGradient: kAetherGradient,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          _poster(versions, Icons.movie_outlined, kAccentPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Titre + badge catégorie
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    displayTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (categoryLabel != null) ...[
                  const SizedBox(width: 8),
                  _categoryBadge(categoryLabel, kAccentPrimary),
                ],
              ]),

              const SizedBox(height: 8),

              // Infos secondaires
              if (isHomonymConflict)
                Text(
                  uniqueYears.join(' · '),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                )
              else if (uniqueChips.isNotEmpty)
                Wrap(spacing: 4, runSpacing: 4, children: uniqueChips),

              const Spacer(),

              // Indicateur multi-versions
              if (versions.length > 1)
                Row(children: [
                  Icon(Icons.layers_outlined, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${versions.length} versions',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── SerieCard ───────────────────────────────────────────────────────────────

class SerieCard extends StatelessWidget {
  final String seriesKey;
  final Map<String, List<M3uEntry>> saisons;
  final void Function(List<M3uEntry>) onEntrySelected;

  const SerieCard({super.key, required this.seriesKey, required this.saisons, required this.onEntrySelected});

  @override
  Widget build(BuildContext context) {
    final cs            = Theme.of(context).colorScheme;
    final displayTitle  = seriesKey;
    final totalEpisodes = saisons.values.fold<int>(0, (p, l) => p + l.length);
    final allVersions   = saisons.values.expand((l) => l).toList();
    // Catégorie calculée depuis les versions (compte prioritaire en premier)
    final categoryLabel = allVersions.isNotEmpty
        ? contentCategoryLabel(allVersions.first.groupTitle)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Barre accent gauche (magenta → purple) via Stack pour éviter
              // l'incompatibilité IntrinsicHeight / ExpansionTile
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kAccentTertiary, kAccentPrimary],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // Contenu décalé de 3px pour laisser place à la barre
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    childrenPadding: EdgeInsets.zero,
                    leading: _poster(allVersions, Icons.tv_outlined, kAccentTertiary),
                    title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (categoryLabel != null) ...[
                        const SizedBox(width: 8),
                        _categoryBadge(categoryLabel, kAccentTertiary),
                      ],
                    ]),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${saisons.keys.length} saison${saisons.keys.length > 1 ? 's' : ''} · $totalEpisodes épisode${totalEpisodes > 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    children: saisons.entries.map((seasonEntry) {
                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                          childrenPadding: EdgeInsets.zero,
                          leading: Icon(Icons.expand_circle_down_outlined, size: 18, color: cs.onSurfaceVariant),
                          title: Text(
                            'Saison ${seasonEntry.key}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          children: seasonEntry.value.map((ep) => _EpisodeTile(
                            ep: ep,
                            onTap: () => onEntrySelected([ep]),
                          )).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final M3uEntry ep;
  final VoidCallback onTap;
  const _EpisodeTile({required this.ep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 10, 16, 10),
        child: Row(children: [
          episodeChip(ep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              episodeName(ep),
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.play_circle_outline_rounded, size: 20, color: kAccentSecondary),
        ]),
      ),
    );
  }
}

// ─── TvCard ──────────────────────────────────────────────────────────────────

class TvCard extends StatelessWidget {
  final String displayName;
  final List<M3uEntry> versions;
  final void Function(List<M3uEntry>) onTap;

  const TvCard({super.key, required this.displayName, required this.versions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final hasReplay = versions.isNotEmpty && versions.first.supportsCatchup;

    return _cardShell(
      context: context,
      onTap: () => onTap(versions),
      accentGradient: LinearGradient(
        colors: [kAccentSecondary, kAccentPrimary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          _poster(versions, Icons.live_tv_outlined, kAccentSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(children: [
                if (versions.length > 1) ...[
                  Icon(Icons.layers_outlined, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${versions.length} flux', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
                if (versions.length > 1 && hasReplay)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                if (hasReplay) ...[
                  Icon(Icons.replay_circle_filled, color: kAccentSecondary, size: 14),
                  const SizedBox(width: 3),
                  Text('Replay', style: TextStyle(color: kAccentSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ]),
            ]),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}
