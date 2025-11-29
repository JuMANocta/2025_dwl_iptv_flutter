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

    // Filtrer et trier la filmographie par année (du plus récent au plus ancien)
    final filmographyList = credits
        .map((c) => FilmographyEntry.fromJson(c))
        .where((c) => c.title.isNotEmpty && c.year != null)
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
  final String mediaType;
  final String? posterPath;
  final String? character;
  final int? year;

  FilmographyEntry({
    required this.id,
    required this.title,
    required this.mediaType,
    this.posterPath,
    this.character,
    this.year,
  });

  factory FilmographyEntry.fromJson(Map<String, dynamic> json) {
    final title = (json['media_type'] == 'movie' ? json['title'] : json['name']) as String? ?? 'Inconnu';

    // Déterminer la date de sortie pour obtenir l'année
    String? dateString = json['media_type'] == 'movie'
        ? json['release_date'] as String?
        : json['first_air_date'] as String?;

    int? year;
    if (dateString != null && dateString.length >= 4) {
      year = int.tryParse(dateString.substring(0, 4));
    }

    return FilmographyEntry(
      id: json['id'] as int,
      title: title,
      mediaType: json['media_type'] as String,
      posterPath: json['poster_path'] as String?,
      character: json['character'] as String?,
      year: year,
    );
  }
}
