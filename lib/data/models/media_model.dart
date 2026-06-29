/// Membre du casting TMDB (acteur + rôle + photo). Utilisé pour afficher les
/// vignettes d'acteurs sur la fiche détail (mobile + TV).
class CastMember {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  const CastMember({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });
}

/// §tmdbReco — Référence légère vers un autre titre TMDB (recommandation ou
/// élément de saga). Sert uniquement à matcher la playlist par titre + année.
class MediaRef {
  final int id;
  final String title;
  final String? year;
  const MediaRef({required this.id, required this.title, this.year});
}

class Media {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double voteAverage;
  final String? releaseDate;
  final List<String> genres;
  final String? runtimeOrEpisodeLength;
  final String? productionCompanies;
  final List<String> cast;
  /// Casting enrichi (id + rôle + photo) pour les vignettes d'acteurs.
  final List<CastMember> castMembers;
  final String? trailerKey;

  /// §tmdbReco — Saga / collection (si le film en fait partie) + recommandations.
  final int? collectionId;
  final String? collectionName;
  final List<MediaRef> recommendations;

  /// §tmdbBadges — Certification d'âge (FR prioritaire, fallback US) : "12",
  /// "16", "TP"/"U"… Null si TMDB ne la fournit pas pour ce pays.
  final String? certification;

  Media({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.overview,
    required this.voteAverage,
    this.releaseDate,
    required this.genres,
    this.runtimeOrEpisodeLength,
    this.productionCompanies,
    required this.cast,
    this.castMembers = const [],
    this.trailerKey,
    this.collectionId,
    this.collectionName,
    this.recommendations = const [],
    this.certification,
  });

  factory Media.fromJson(Map<String, dynamic> json) {
    final isMovie = json.containsKey('title');

    // 1. Extraction des acteurs du champ 'credits'
    final rawCast = (json['credits']?['cast'] as List<dynamic>?) ?? const [];
    // Noms (compat existante) — 5 premiers.
    final castList = rawCast
        .take(5)
        .map((a) => a['name'] as String)
        .toList();
    // Casting enrichi (id + rôle + photo) — 12 premiers pour le carrousel acteurs.
    final castMembersList = rawCast
        .take(12)
        .where((a) => a['id'] != null && a['name'] != null)
        .map((a) => CastMember(
              id: a['id'] as int,
              name: a['name'] as String,
              character: a['character'] as String?,
              profilePath: a['profile_path'] as String?,
            ))
        .toList();

    // 2. Recherche de la première bande-annonce (Trailer) en FR ou ANGLAIS
    String? foundTrailerKey;
    final videos = json['videos']?['results'] as List<dynamic>?;
    if (videos != null) {
      // Tente de trouver la première bande-annonce (Trailer/Teaser) en français
      final frTrailer = videos.firstWhere(
              (v) => (v['type'] == 'Trailer' || v['type'] == 'Teaser') && v['iso_639_1'] == 'fr',
          orElse: () => null);

      // Si pas de français, prend le meilleur trailer global
      final primaryTrailer = frTrailer ?? videos.firstWhere(
              (v) => (v['type'] == 'Trailer' || v['type'] == 'Teaser'),
          orElse: () => null);

      if (primaryTrailer != null) {
        foundTrailerKey = primaryTrailer['key'] as String;
      }
    }

    // Extraction des genres
    final genresList = (json['genres'] as List<dynamic>?)
        ?.map((g) => g['name'] as String)
        .toList() ?? [];

    // Extraction des durées (Movie: runtime, TV: episode_run_time)
    String? runtime;
    if (isMovie) {
      final rt = json['runtime'] as int?;
      if (rt != null && rt > 0) {
        runtime = '${rt ~/ 60}h ${rt % 60}m';
      }
    } else {
      final epTimes = json['episode_run_time'] as List<dynamic>?;
      if (epTimes != null && epTimes.isNotEmpty) {
        runtime = '${epTimes[0]}m/épisode';
      }
    }

    // Extraction des compagnies (les 3 premières)
    final companies = (json['production_companies'] as List<dynamic>?)
        ?.take(3)
        .map((c) => c['name'] as String)
        .join(', ');

    // §tmdbReco — Saga + recommandations (même type que le média parent).
    final coll = json['belongs_to_collection'] as Map<String, dynamic>?;
    final recos = <MediaRef>[];
    for (final r in (json['recommendations']?['results'] as List<dynamic>?) ??
        const []) {
      if (r is! Map<String, dynamic>) continue;
      final rid = r['id'] as int?;
      final rtitle = (r['title'] ?? r['name']) as String?;
      if (rid == null || rtitle == null || rtitle.isEmpty) continue;
      final rdate = (r['release_date'] ?? r['first_air_date']) as String?;
      recos.add(MediaRef(
        id: rid,
        title: rtitle,
        year: (rdate != null && rdate.length >= 4) ? rdate.substring(0, 4) : null,
      ));
    }

    // §tmdbBadges — Certification d'âge. Films : `release_dates.results[].
    // release_dates[].certification`. Séries : `content_ratings.results[].
    // rating`. Priorité FR → US → 1re valeur non vide.
    String? certification;
    {
      String? pick(List<dynamic> results, String? Function(Map) cert) {
        String? fr, us, any;
        for (final r in results) {
          if (r is! Map) continue;
          final iso = (r['iso_3166_1'] ?? '').toString().toUpperCase();
          final c = cert(r);
          if (c == null || c.isEmpty) continue;
          if (iso == 'FR') {
            fr = c;
          } else if (iso == 'US') {
            us = c;
          }
          any ??= c;
        }
        return fr ?? us ?? any;
      }

      if (isMovie) {
        final results =
            (json['release_dates']?['results'] as List<dynamic>?) ?? const [];
        certification = pick(results, (r) {
          final rd = (r['release_dates'] as List<dynamic>?) ?? const [];
          for (final d in rd) {
            final c = (d is Map ? d['certification'] : null)?.toString();
            if (c != null && c.isNotEmpty) return c;
          }
          return null;
        });
      } else {
        final results =
            (json['content_ratings']?['results'] as List<dynamic>?) ?? const [];
        certification = pick(results, (r) => r['rating']?.toString());
      }
    }

    return Media(
      id: json['id'] as int,
      title: (isMovie ? json['title'] : json['name']) as String,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String? ?? 'N/A',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: (isMovie ? json['release_date'] : json['first_air_date']) as String?,
      genres: genresList,
      runtimeOrEpisodeLength: runtime,
      productionCompanies: companies,
      cast: castList,
      castMembers: castMembersList,
      trailerKey: foundTrailerKey,
      collectionId: coll?['id'] as int?,
      collectionName: coll?['name'] as String?,
      recommendations: recos,
      certification: certification,
    );
  }
}