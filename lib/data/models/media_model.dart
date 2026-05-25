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
    );
  }
}