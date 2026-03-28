class Person {
  final int id;
  final String name;
  final String? profilePath;
  final String? biography;
  final List<FilmographyEntry> filmography;

  Person({
    required this.id,
    required this.name,
    this.profilePath,
    this.biography,
    required this.filmography,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    // Parsing filmography from 'combined_credits'
    final credits = json['combined_credits']?['cast'] as List<dynamic>? ?? [];

    // Dédupliquer par id TMDB — une série peut apparaître N fois (N épisodes)
    final seen = <int>{};
    final filmographyList = credits
        .map((c) => FilmographyEntry.fromJson(c))
        .where((c) => c.title.isNotEmpty && c.year != null && seen.add(c.id))
        .toList();

    filmographyList.sort((a, b) => b.year!.compareTo(a.year!));

    return Person(
      id: json['id'] as int,
      name: json['name'] as String,
      profilePath: json['profile_path'] as String?,
      biography: json['biography'] as String?,
      filmography: filmographyList,
    );
  }
}

class FilmographyEntry {
  final int id;
  final String title;
  /// Titre original (en VO) — souvent utilisé par les providers IPTV dans leurs playlists.
  final String? originalTitle;
  final String mediaType;
  final String? posterPath;
  final String? character;
  final int? year;

  FilmographyEntry({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.mediaType,
    this.posterPath,
    this.character,
    this.year,
  });

  factory FilmographyEntry.fromJson(Map<String, dynamic> json) {
    final isMovie = json['media_type'] == 'movie';
    final title = (isMovie ? json['title'] : json['name']) as String? ?? 'Inconnu';
    final originalTitle = (isMovie ? json['original_title'] : json['original_name']) as String?;

    // Déterminer la date de sortie pour obtenir l'année
    final dateString = isMovie
        ? json['release_date'] as String?
        : json['first_air_date'] as String?;

    int? year;
    if (dateString != null && dateString.length >= 4) {
      year = int.tryParse(dateString.substring(0, 4));
    }

    return FilmographyEntry(
      id: json['id'] as int,
      title: title,
      originalTitle: originalTitle,
      mediaType: json['media_type'] as String,
      posterPath: json['poster_path'] as String?,
      character: json['character'] as String?,
      year: year,
    );
  }
}
