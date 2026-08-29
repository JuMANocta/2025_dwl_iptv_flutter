/// §inferredCat — Traduction des genres TMDB vers le vocabulaire de catégories
/// déjà utilisé par l'application.
///
/// **Pourquoi cette table existe.** Certaines listes ne fournissent AUCUNE
/// information de catégorie : le format « Ultimate » (`URL#Name:Titre`) ne porte
/// ni `group-title` ni rien d'équivalent, et l'API JSON du même panel répond
/// `live=0 vod=0 series=0`. Mesuré sur une liste réelle : **153 062 entrées sur
/// 153 062 sans groupe**, donc 100 % dans « Autres ». Il n'y a rien à traduire —
/// il faut fabriquer la catégorie.
///
/// ⚠️ **Les libellés sont volontairement ceux de `contentCategoryLabel`**
/// (`m3u_filter.dart`) et non les noms TMDB. Tout l'intérêt est que la
/// catégorie inférée d'une liste pauvre **fusionne** avec celle d'une liste
/// riche : « Action » doit tomber dans la même rangée des deux côtés, sinon on
/// aurait deux rangées Action côte à côte et le rangement serait pire qu'avant.
library;

/// Genres TMDB → libellé de catégorie de l'app.
///
/// Couvre les identifiants FILM et SÉRIE (TMDB en utilise deux jeux distincts,
/// avec des recouvrements partiels).
const Map<int, String> kTmdbGenreLabels = {
  // ── Films ────────────────────────────────────────────────────────────────
  28: 'Action',
  12: 'Aventure',
  16: 'Animation',
  35: 'Comédie',
  80: 'Crime',
  99: 'Documentaire',
  18: 'Drame',
  10751: 'Enfants',
  14: 'Fantastique',
  36: 'Histoire',
  27: 'Horreur',
  10402: 'Musique',
  9648: 'Thriller', // Mystère → rangé avec Thriller (l'app n'a pas « Mystère »)
  10749: 'Romance',
  878: 'Sci-Fi',
  10770: 'Téléfilm',
  53: 'Thriller',
  10752: 'Guerre',
  37: 'Western',

  // ── Séries ───────────────────────────────────────────────────────────────
  10759: 'Action', // Action & Adventure
  10762: 'Enfants',
  10763: 'Documentaire', // News → le plus proche dans le vocabulaire de l'app
  10764: 'Téléréalité',
  10765: 'Sci-Fi', // Sci-Fi & Fantasy
  10766: 'Drame', // Soap
  10767: 'Talk-show',
  10768: 'Guerre', // War & Politics
};

/// Choisit LE libellé à retenir parmi les genres d'un titre.
///
/// TMDB en renvoie souvent trois ou quatre (« Action, Thriller, Crime »). Une
/// catégorie doit être unique, donc il faut trancher — et le premier genre
/// renvoyé par TMDB n'est pas toujours le plus parlant : il est fréquent que
/// « Drame » arrive en tête d'un film qui est avant tout un thriller.
///
/// On applique donc un ordre de spécificité : un genre qui DÉCRIT le film
/// (Animation, Documentaire, Horreur…) prime sur les genres fourre-tout
/// (Drame, Action), qui s'appliquent à presque tout.
String? tmdbGenreLabel(List<int> genreIds) {
  if (genreIds.isEmpty) return null;
  const priority = <String>[
    'Animation',
    'Documentaire',
    'Horreur',
    'Western',
    'Musique',
    'Guerre',
    'Histoire',
    'Enfants',
    'Téléréalité',
    'Talk-show',
    'Téléfilm',
    'Sci-Fi',
    'Fantastique',
    'Romance',
    'Comédie',
    'Thriller',
    'Crime',
    'Aventure',
    'Action',
    'Drame',
  ];
  final labels = <String>{
    for (final id in genreIds)
      if (kTmdbGenreLabels[id] != null) kTmdbGenreLabels[id]!,
  };
  if (labels.isEmpty) return null;
  for (final p in priority) {
    if (labels.contains(p)) return p;
  }
  return labels.first;
}
