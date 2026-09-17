/// R44 — Le NOYAU unique de la règle « cette URL est le marqueur d'une série
/// entière », partagé par l'accueil et la fiche.
///
/// Le catalogue Xtream ne donne pas d'endpoint de stream pour une série : il
/// donne UNE entrée par série, dont l'URL `/series/{user}/{pass}/{series_id}`
/// n'est qu'un porte-identifiant. C'est la fiche qui s'en sert pour aller
/// chercher les épisodes à la demande (`player_api.php`), et c'est l'accueil
/// qui s'en sert pour ne pas proposer « Lire » sur un chemin injouable.
///
/// ⛔ **Cette règle était écrite DEUX fois** : `isSeriesStubEntry`
/// (`home_card.dart`, R38) et `DetailsPage._extractSeriesIdFromUrl`. Les deux
/// copies portaient le même noyau, à la ligne près — et c'est exactement le
/// piège §tourFix, que le projet a déjà payé sur `redactUrl` : deux copies
/// d'une règle finissent toujours par diverger, et la divergence se paie en
/// identifiants en clair ou, ici, en désaccord entre l'accueil et la fiche sur
/// ce qu'est un stub. Un seul prédicat désormais ; les deux appelants posent
/// leurs gardes PROPRES par-dessus (type de contenu, titre numéroté), qui ne
/// sont pas la même question.
library;

import '../../data/models/m3u_entry.dart';

/// Le `series_id` porté par [url] si elle est le stub d'une série, `null`
/// sinon.
///
/// Reconnu : au moins 4 segments de chemin, premier segment `series`
/// (insensible à la casse), dernier segment sans point (un point = une
/// extension, donc une URL d'ÉPISODE bien réelle) et entier.
///
/// ⚠️ Rendre `null` ne veut pas dire « ce n'est pas une série » : ça veut dire
/// « on ne saurait pas en tirer d'épisodes ». Les deux appelants en ont besoin
/// pour des raisons opposées — la fiche veut l'identifiant, l'accueil veut
/// seulement savoir si l'URL est jouable telle quelle.
///
/// Fonction pure : c'est elle qu'on teste.
int? seriesIdFromUrl(String url) {
  try {
    final List<String> segments = Uri.parse(url).pathSegments;
    if (segments.length < 4 || segments.first.toLowerCase() != 'series') {
      return null;
    }
    final String last = segments.last;
    if (last.contains('.')) return null; // une extension = URL d'épisode
    return int.tryParse(last);
  } catch (_) {
    // Une URL que `Uri.parse` refuse n'est le stub de rien.
    return null;
  }
}

/// `true` quand [url] est le stub d'une série — le même verdict que
/// [seriesIdFromUrl], quand l'identifiant lui-même n'intéresse pas l'appelant.
bool isSeriesStubUrl(String url) => seriesIdFromUrl(url) != null;

/// R38 — `true` quand [entry] est le **stub** d'une série : l'unique entrée que
/// le catalogue Xtream porte pour la série entière, dont l'URL n'est pas un
/// endpoint de stream mais un porte-identifiant.
///
/// ⚠️ Une série ne se reconnaît PAS à son type : une liste M3U porte ses
/// épisodes comme autant d'entrées `series` à l'URL bien réelle (§Ultimate,
/// `SxxExx`), et ceux-là se lisent. C'est la FORME de l'URL qui tranche —
/// [seriesIdFromUrl] — sous deux gardes qui, elles, sont propres à la question
/// « puis-je lire cette entrée telle quelle ? ».
///
/// Fonction pure : c'est elle qu'on teste.
bool isSeriesStubEntry(M3uEntry entry) {
  if (entry.type != M3uContentType.series) return false;
  // Épisode numéroté (liste M3U) : son URL est jouable telle quelle.
  //
  // ⚠️ **Ce court-circuit ne protège d'aucun cas mesuré** : sur les 231 252 URL
  // `/series/` des deux M3U réels, aucune ne porte à la fois une numérotation
  // et une URL sans extension — le test d'extension de [seriesIdFromUrl] les
  // attrape déjà toutes. Sa valeur est la PARITÉ avec la fiche :
  // `_buildSeasonEpisodes` teste lui aussi le TITRE avant l'URL.
  if (entry.title.isSeriesEpisode) return false;
  return isSeriesStubUrl(entry.url);
}

/// **R45 — la première version du groupe qu'on peut réellement LIRE**, `null`
/// si le groupe n'en contient aucune.
///
/// ⛔ **Ne jamais décider sur `versions.first`.** Un même titre MÉLANGE
/// couramment le stub d'API d'un compte Xtream et les épisodes réels d'une
/// liste M3U : mesuré sur les six dumps réels, **5 836 groupes de série sur
/// 21 025 sont mixtes — 27,76 %**, dont 1 053 pour un seul fournisseur exposé à
/// la fois en JSON (stubs) et en M3U (épisodes). Et l'élément de TÊTE n'est pas
/// une propriété du contenu : il dépend de l'ORDRE D'AJOUT DES COMPTES par
/// l'utilisateur — dans un sens 100 % des têtes sont des épisodes, dans l'autre
/// 100 % sont des stubs. Une décision prise sur la tête est donc un tirage au
/// sort.
///
/// ⚠️ La question qui vaut n'est pas « ce groupe contient-il un stub ? » mais
/// « ce groupe contient-il quelque chose à lire ? ». Interroger la présence
/// (`versions.any(isSeriesStubEntry)`) coûtait « Télécharger » à ces 5 836
/// groupes, alors qu'ils portent des épisodes parfaitement téléchargeables.
///
/// ⚠️ Un groupe mixte se comporte donc désormais comme un groupe purement M3U,
/// ce qui est le comportement déjà en place et accepté pour ceux-là. Ce n'est
/// PAS le défaut d'origine de R38, qui était de pousser au lecteur une URL qui
/// n'aboutit jamais : ici la lecture aboutit.
///
/// Fonction pure : c'est elle qu'on teste.
M3uEntry? firstPlayableVersion(Iterable<M3uEntry> versions) {
  for (final M3uEntry v in versions) {
    if (!isSeriesStubEntry(v)) return v;
  }
  return null;
}

/// R45 — `true` quand le groupe n'offre QUE des stubs : la seule destination
/// honnête est alors la fiche (« Choisir un épisode »), qui sait aller chercher
/// les épisodes derrière l'identifiant.
///
/// ⚠️ Un groupe VIDE n'est pas « tout stub » : il n'est rien, et l'appelant
/// s'arrête avant d'arriver ici.
bool groupIsOnlySeriesStubs(Iterable<M3uEntry> versions) =>
    versions.isNotEmpty && firstPlayableVersion(versions) == null;

/// R38 — `true` si le groupe contient AU MOINS un stub de série.
///
/// ⚠️ Conservé pour ce qu'il dit vraiment (« ce groupe a une fiche de série
/// derrière lui »), mais ⛔ **ce n'est PAS la question à poser pour décider
/// d'une tuile** : c'est ce qu'a corrigé R45 — voir [firstPlayableVersion].
bool groupHasSeriesStub(Iterable<M3uEntry> versions) =>
    versions.any(isSeriesStubEntry);
