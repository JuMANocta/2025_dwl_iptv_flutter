class Person {
  final int id;
  final String name;
  final String? profilePath;
  final String? biography;
  final List<FilmographyEntry> filmography;

  /// §directorView — Métier principal renvoyé par TMDB (`known_for_department`) :
  /// "Acting", "Directing", "Writing"… Sert à adapter les libellés de la fiche
  /// (« Filmographie (Réalisation) » vs « (Rôles) »).
  final String? knownForDepartment;

  /// Vrai si la personne est avant tout réalisatrice/réalisateur.
  bool get isDirector => knownForDepartment == 'Directing';

  Person({
    required this.id,
    required this.name,
    this.profilePath,
    this.biography,
    required this.filmography,
    this.knownForDepartment,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    // §directorView — On fusionne `cast` ET `crew` de `combined_credits`.
    // AVANT : seul `cast` était lu → la fiche d'un RÉALISATEUR s'affichait avec
    // une filmographie quasi vide (uniquement ses caméos d'acteur), ce qui
    // rendait la navigation « voir ses autres films » inutile.
    final combined = json['combined_credits'] as Map<String, dynamic>?;
    final rawCast = (combined?['cast'] as List<dynamic>?) ?? const [];
    final rawCrew = (combined?['crew'] as List<dynamic>?) ?? const [];

    final entries = <FilmographyEntry>[];
    // Réalisation d'abord : en cas de doublon (réalisateur qui joue aussi dans
    // son film), c'est ce crédit-là qu'on veut garder.
    for (final c in rawCrew) {
      if (c is! Map<String, dynamic>) continue;
      final job = c['job'] as String?;
      final dept = c['department'] as String?;
      if (job != 'Director' && dept != 'Directing') continue;
      entries.add(FilmographyEntry.fromJson(c));
    }
    for (final c in rawCast) {
      if (c is! Map<String, dynamic>) continue;
      entries.add(FilmographyEntry.fromJson(c));
    }

    // Dédup par id TMDB — une série apparaît N fois (N épisodes), et un titre
    // peut être présent dans crew ET cast (le premier inséré gagne).
    final seen = <int>{};
    final filmographyList = entries
        .where((c) => c.title.isNotEmpty && c.year != null && seen.add(c.id))
        .toList();

    filmographyList.sort((a, b) => b.year!.compareTo(a.year!));

    return Person(
      id: json['id'] as int,
      name: json['name'] as String,
      profilePath: json['profile_path'] as String?,
      biography: json['biography'] as String?,
      filmography: filmographyList,
      knownForDepartment: json['known_for_department'] as String?,
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

  /// §directorView — Fonction occupée sur ce titre ("Director"…). Null quand
  /// l'entrée vient du casting (c'est alors [character] qui est renseigné).
  final String? job;

  FilmographyEntry({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.mediaType,
    this.posterPath,
    this.character,
    this.year,
    this.job,
  });

  factory FilmographyEntry.fromJson(Map<String, dynamic> json) {
    // §directorView — `media_type` était casté en non-null (`as String`), ce
    // qui LEVAIT sur les entrées qui ne le portent pas (certains crédits
    // `crew`). On retombe sur le type déduit des champs présents.
    final rawType = json['media_type'] as String?;
    final looksLikeMovie =
        json.containsKey('title') || json.containsKey('release_date');
    final mediaType = rawType ?? (looksLikeMovie ? 'movie' : 'tv');
    final isMovie = mediaType == 'movie';

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
      mediaType: mediaType,
      posterPath: json['poster_path'] as String?,
      character: json['character'] as String?,
      year: year,
      job: json['job'] as String?,
    );
  }
}
