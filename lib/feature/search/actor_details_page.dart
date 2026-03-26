import 'package:flutter/material.dart';
import '../../data/services/tmdb_service.dart';
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

  @override
  void initState() {
    super.initState();
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

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[''`´]"), '')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Retourne les entrées M3U correspondant au crédit.
  /// Passe 1 : égalité exacte normalisée.
  /// Passe 2 : l'un contient l'autre (min 3 caractères).
  List<M3uEntry> _findMatches(FilmographyEntry credit) {
    final target = _norm(credit.title);
    if (target.length < 3) return [];

    final type = credit.mediaType == 'movie'
        ? M3uContentType.movie
        : M3uContentType.series;

    // Passe 1 — exact
    final exact = _lookup[target];
    if (exact != null) {
      final filtered = exact.where((e) => e.type == type).toList();
      if (filtered.isNotEmpty) return filtered;
    }

    // Passe 2 — partiel
    final results = <M3uEntry>[];
    for (final entry in ParsedPlaylistService.entries) {
      if (entry.type != type) continue;
      final key = _norm(entry.displayName);
      if (key.length < 3) continue;
      if (key.contains(target) || target.contains(key)) {
        results.add(entry);
      }
    }
    return results;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

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

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280.0,
                pinned: true,
                backgroundColor: cs.surface,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(person.name,
                      style: const TextStyle(
                          shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
                  centerTitle: false,
                  background: (profileUrl != null)
                      ? Image.network(profileUrl, fit: BoxFit.cover)
                      : Container(color: cs.surfaceContainerHighest),
                ),
              ),

              SliverList(
                delegate: SliverChildListDelegate([
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
                          // Pour les films : tappable → DetailsPage
                          final canNavigate =
                              isAvailable && credit.mediaType == 'movie';

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
                            subtitle: Text(
                              'Rôle : ${credit.character ?? 'N/A'}',
                              style: TextStyle(color: cs.onSurfaceVariant),
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
    final color   = isMovie ? Colors.blue : Colors.purple;
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
        color: Colors.green.withAlpha(35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tappable ? Icons.play_circle_outline : Icons.check,
            size: 11,
            color: Colors.green,
          ),
          const SizedBox(width: 3),
          const Text(
            'DISPO',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
