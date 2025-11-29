class Media {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double voteAverage;
  final String? releaseDate;

  // 🎯 NOUVEAUX CHAMPS
  final List<String> genres; // Liste des noms des genres (ex: "Mystère", "Thriller")
  final String? runtimeOrEpisodeLength; // Durée du film ou des épisodes (pour TV)
  final String? productionCompanies; // Noms des principales sociétés

  Media({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.overview,
    required this.voteAverage,
    this.releaseDate,
    // NOUVEAU
    required this.genres,
    this.runtimeOrEpisodeLength,
    this.productionCompanies,
  });

  factory Media.fromJson(Map<String, dynamic> json) {
    final isMovie = json.containsKey('title');

    // Extraction des genres (Conversion de List<Map> en List<String>)
    final genresList = (json['genres'] as List<dynamic>?)
        ?.map((g) => g['name'] as String)
        .toList() ?? [];

    // Extraction des durées (Movie: runtime, TV: episode_run_time)
    String? runtime;
    if (isMovie) {
      final rt = json['runtime'] as int?;
      if (rt != null && rt > 0) {
        runtime = '${rt ~/ 60}h ${rt % 60}m'; // Format "1h 30m"
      }
    } else {
      final epTimes = json['episode_run_time'] as List<dynamic>?;
      if (epTimes != null && epTimes.isNotEmpty) {
        runtime = '${epTimes[0]}m/épisode';
      }
    }

    // Extraction des compagnies (les 2-3 premières)
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
    );
  }
}
