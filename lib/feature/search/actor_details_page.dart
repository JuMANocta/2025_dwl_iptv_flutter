import 'package:flutter/material.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/tmdb_api_service.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/models/person_model.dart';
import '../../data/models/m3u_entry.dart';
import '../../widgets/aether_image.dart';
import '../../widgets/tv/focusable_card.dart';
import 'details_page.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';

class ActorDetailsPage extends StatefulWidget {
  final int personId;
  const ActorDetailsPage({super.key, required this.personId});

  @override
  State<ActorDetailsPage> createState() => _ActorDetailsPageState();
}

class _ActorDetailsPageState extends State<ActorDetailsPage> with TvInitialFocus {
  // Index depuis la mémoire ParsedPlaylistService : titre normalisé → toutes
  // les entrées correspondantes (toutes qualités). Reconstruit quand la
  // playlist change (cf. `_refreshLookup`).
  Map<String, List<M3uEntry>> _lookup = const {};
  bool _hasTmdbKey = false;

  /// §directorView — Future MÉMOÏSÉ. Avant, `getPersonDetails` était appelé
  /// directement dans `build()` → une requête réseau relancée à CHAQUE rebuild
  /// (scroll, focus, setState de la clé TMDB…).
  late final Future<Person?> _personFuture;

  /// §tmdbOnlyDetails — Version de playlist ayant servi à bâtir [_lookup].
  /// Les comptes SECONDAIRES sont hydratés en arrière-plan au boot
  /// (`main.dart:_hydrateSecondaryAccounts`) : un index figé en `initState`
  /// marquait « non dispo » à vie les titres de ces comptes quand la fiche
  /// était ouverte pendant le chargement.
  int _lookupVersion = -1;

  @override
  void initState() {
    super.initState();
    _refreshLookup();
    ParsedPlaylistService.version.addListener(_onPlaylistChanged);
    _personFuture = TmdbService.instance.getPersonDetails(widget.personId);
    TmdbApiService.hasApiKey().then((v) {
      if (mounted) setState(() => _hasTmdbKey = v);
    });
  }

  @override
  void dispose() {
    ParsedPlaylistService.version.removeListener(_onPlaylistChanged);
    super.dispose();
  }

  void _onPlaylistChanged() {
    if (!mounted) return;
    setState(_refreshLookup);
  }

  /// Reconstruit l'index seulement si la playlist a changé (l'index couvre
  /// TOUTES les entrées : à ne pas refaire à chaque rebuild).
  void _refreshLookup() {
    final v = ParsedPlaylistService.version.value;
    if (_lookupVersion == v) return;
    _lookupVersion = v;
    _lookup = _buildLookup();
  }

  // ── Helpers de matching ────────────────────────────────────────────────────

  static Map<String, List<M3uEntry>> _buildLookup() {
    final map = <String, List<M3uEntry>>{};
    for (final e in ParsedPlaylistService.entries) {
      map.putIfAbsent(_norm(e.displayName), () => []).add(e);
    }
    return map;
  }

  /// §parseAudit2026-06-30 — Délègue à `TitleMetadata.computeGroupKey` (voir
  /// justification identique dans `HomePage._normTitle`) au lieu d'une regex
  /// ASCII-only dupliquée qui strippait les accents.
  static String _norm(String s) => TitleMetadata.computeGroupKey(s);

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
        future: _personFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Text('Erreur : fiche introuvable sur TMDB.',
                  style: TextStyle(color: kError)),
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
                      // §imgDiskCache — cache disque ; §imgPerf cap 720 px.
                      AetherImage(
                        url: profileUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                        fallback: (_) =>
                            Container(color: cs.surfaceContainerHighest),
                      ),
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

                        // FILMOGRAPHIE — §directorView : intitulé selon le
                        // métier principal (la page sert acteurs ET
                        // réalisateurs depuis la recherche par personne).
                        Text(
                            person.isDirector
                                ? 'Filmographie (Réalisation)'
                                : 'Filmographie (Rôles)',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: cs.onSurface)),
                        Divider(color: cs.outlineVariant),

                        ...person.filmography.map((credit) {
                          final matches = _findMatches(credit);
                          final isAvailable = matches.isNotEmpty;
                          // §tmdbOnlyDetails — TOUTE ligne est désormais
                          // ouvrable : dispo → fiche normale (lecture,
                          // téléchargement) ; absente → fiche TMDB seule.
                          // Avant, `canNavigate = isAvailable && _hasTmdbKey`
                          // rendait les lignes non-dispo inertes : on appuyait,
                          // il ne se passait rien. La rangée « Personnes » de la
                          // recherche (§personSearch) y menant très souvent, ce
                          // cul-de-sac était devenu le cas fréquent.
                          final canNavigate = _hasTmdbKey;
                          void openDetails() {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => isAvailable
                                    ? DetailsPage(
                                        entry: matches.first,
                                        versions: matches,
                                      )
                                    : DetailsPage.fromTmdb(
                                        tmdbId: credit.id,
                                        title: credit.title,
                                        type: credit.mediaType == 'movie'
                                            ? M3uContentType.movie
                                            : M3uContentType.series,
                                      ),
                              ),
                            );
                          }

                          final tile = ListTile(
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
                                // §directorView — « Réalisateur » sur un crédit
                                // de réalisation, « Rôle : X » sur un crédit
                                // de casting. La ligne disparaît si aucun des
                                // deux n'est renseigné (au lieu de « N/A »).
                                if (credit.job != null)
                                  Text(
                                    credit.job == 'Director'
                                        ? 'Réalisateur'
                                        : credit.job!,
                                    style: TextStyle(color: kAccentSecondary),
                                  )
                                else if (credit.character?.trim().isNotEmpty ==
                                    true)
                                  Text(
                                    'Rôle : ${credit.character}',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
                                  ),
                              ],
                            ),
                            onTap: canNavigate ? openDetails : null,
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

                          // §tvRails — Sur TV, chaque ligne de filmographie est
                          // focusable (FocusableCard) pour une navigation D-pad
                          // ligne par ligne. Avant, seules les lignes DISPO (avec
                          // onTap) étaient focusables → le focus sautait par-dessus
                          // tous les films non disponibles. Les lignes non-DISPO
                          // restent focusables (lecture) mais sans action sur OK.
                          if (!PlatformTv.isTv) return tile;
                          return FocusableCard(
                            scaleOnFocus: false,
                            decorateOnly: true,
                            borderRadius: BorderRadius.circular(8),
                            onTap: canNavigate ? openDetails : null,
                            child: tile,
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
