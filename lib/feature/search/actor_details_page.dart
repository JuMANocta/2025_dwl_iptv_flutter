import 'package:flutter/material.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/tmdb_api_service.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/models/person_model.dart';
import '../../data/models/m3u_entry.dart';
import 'details_page.dart';

class ActorDetailsPage extends StatefulWidget {
  final int personId;
  const ActorDetailsPage({super.key, required this.personId});

  @override
  State<ActorDetailsPage> createState() => _ActorDetailsPageState();
}

class _ActorDetailsPageState extends State<ActorDetailsPage> {
  // Lookup construit une fois depuis la mémoire ParsedPlaylistService :
  // titre normalisé → toutes les entrées correspondantes (toutes qualités).
  late final Map<String, List<M3uEntry>> _lookup;
  bool _hasTmdbKey = false;

  @override
  void initState() {
    super.initState();
    _lookup = _buildLookup();
    TmdbApiService.hasApiKey().then((v) {
      if (mounted) setState(() => _hasTmdbKey = v);
    });
  }

  // ── Helpers de matching ────────────────────────────────────────────────────

  static Map<String, List<M3uEntry>> _buildLookup() {
    final map = <String, List<M3uEntry>>{};
    for (final e in ParsedPlaylistService.entries) {
      map.putIfAbsent(_norm(e.displayName), () => []).add(e);
    }
    return map;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[''`´]"), '')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Retourne les entrées M3U correspondant au crédit.
  /// Passe 1 : égalité exacte normalisée sur le titre localisé.
  /// Passe 2 : égalité exacte normalisée sur le titre original (VO).
  /// Pas de matching flou — évite les faux positifs.
  List<M3uEntry> _findMatches(FilmographyEntry credit) {
    final type = credit.mediaType == 'movie'
        ? M3uContentType.movie
        : M3uContentType.series;

    // Passe 1 — titre localisé exact
    final target = _norm(credit.title);
    if (target.length >= 2) {
      final exact = _lookup[target];
      if (exact != null) {
        final filtered = exact.where((e) => e.type == type).toList();
        if (filtered.isNotEmpty) return filtered;
      }
    }

    // Passe 2 — titre original exact (souvent utilisé par les providers IPTV)
    if (credit.originalTitle != null) {
      final origTarget = _norm(credit.originalTitle!);
      if (origTarget.length >= 2 && origTarget != target) {
        final origExact = _lookup[origTarget];
        if (origExact != null) {
          final filtered = origExact.where((e) => e.type == type).toList();
          if (filtered.isNotEmpty) return filtered;
        }
      }
    }

    return [];
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  /// §tvDetailsShrink — Réduit le contenu de la fiche acteur sur TV : largeur max
  /// centrée (820) + texte mis à l'échelle (0.85). Neutre sur mobile.
  Widget _tvShrink(BuildContext context, bool isTv, Widget child) {
    if (!isTv) return child;
    final mq = MediaQuery.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820.0),
        child: MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(0.85)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: FutureBuilder<Person?>(
        future: TmdbService.instance.getPersonDetails(widget.personId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Text('Erreur : Fiche Acteur non trouvée.',
                  style: TextStyle(color: Colors.red.shade400)),
            );
          }

          final person     = snapshot.data!;
          final profileUrl = TmdbService.getPosterUrl(person.profilePath, size: 'w342');

          // §tvDetailsShrink — Mêmes leviers que DetailsPage : sur TV, backdrop
          // réduit + contenu en largeur max centrée + texte mis à l'échelle.
          final bool isTvPlatform = PlatformTv.isTv;
          final double screenH = MediaQuery.sizeOf(context).height;
          final double headerHeight =
              isTvPlatform ? (screenH * 0.42).clamp(180.0, 300.0) : 280.0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: headerHeight,
                pinned: true,
                backgroundColor: cs.surface,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(person.name,
                      style: const TextStyle(
                          shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
                  centerTitle: false,
                  // §castPhotos — Header façon fiche film : image + dégradé de
                  // lisibilité (transparent → noir → surface) pour le nom et une
                  // transition douce vers le contenu.
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (profileUrl != null)
                        Image.network(
                          profileUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: cs.surfaceContainerHighest),
                        )
                      else
                        Container(color: cs.surfaceContainerHighest),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black54,
                              cs.surface,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildListDelegate([
                  _tvShrink(
                    context,
                    isTvPlatform,
                    Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // BIOGRAPHIE
                        Text('Biographie',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: cs.onSurface)),
                        Divider(color: cs.outlineVariant),
                        Text(
                          person.biography ?? 'Biographie indisponible.',
                          style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                        ),
                        const SizedBox(height: 32),

                        // FILMOGRAPHIE
                        Text('Filmographie (Rôles)',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: cs.onSurface)),
                        Divider(color: cs.outlineVariant),

                        ...person.filmography.map((credit) {
                          final matches = _findMatches(credit);
                          final isAvailable = matches.isNotEmpty;
                          // Films ET séries : tappable → DetailsPage (si clé TMDB configurée)
                          final canNavigate = isAvailable && _hasTmdbKey;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Text(
                              credit.year?.toString() ?? 'N/A',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            title: Text(
                              credit.title,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: isAvailable
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (credit.originalTitle != null &&
                                    credit.originalTitle != credit.title)
                                  Text(
                                    credit.originalTitle!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                        fontStyle: FontStyle.italic),
                                  ),
                                Text(
                                  'Rôle : ${credit.character ?? 'N/A'}',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            onTap: canNavigate
                                ? () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DetailsPage(
                                          entry: matches.first,
                                          versions: matches,
                                        ),
                                      ),
                                    )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Badge type (movie / tv)
                                _typeChip(credit.mediaType, cs),
                                // Badge DISPO si présent dans la playlist
                                if (isAvailable) ...[
                                  const SizedBox(width: 6),
                                  _dispoChip(canNavigate),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _typeChip(String mediaType, ColorScheme cs) {
    final isMovie = mediaType == 'movie';
    final color   = isMovie ? kBadgeFilmType : kBadgeSeriesType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        isMovie ? 'FILM' : 'SÉRIE',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _dispoChip(bool tappable) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kDispo.withAlpha(35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kDispo.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tappable ? Icons.play_circle_outline : Icons.check,
            size: 11,
            color: kDispo,
          ),
          const SizedBox(width: 3),
          Text(
            'DISPO',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: kDispo),
          ),
        ],
      ),
    );
  }
}
