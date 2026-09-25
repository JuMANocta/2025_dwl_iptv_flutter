import '../../data/models/m3u_entry.dart';
import 'm3u_filter.dart';
import 'series_stub.dart';

/// §detailsLive — Ce qu'une fiche doit savoir de la MÉMOIRE, en règles pures.
///
/// **Le défaut réparé.** Une fiche de FILM figeait ses versions au moment du
/// tap : elle affichait la liste que l'accueil lui avait passée et ne la
/// recalculait plus jamais. Quand une liste revenait (rechargement, ré-analyse
/// terminée, retour de mémoire), ses qualités n'apparaissaient qu'après avoir
/// refermé puis rouvert la fiche. Les séries, elles, repartaient bien de la
/// mémoire à l'ouverture (`_buildSeasonEpisodes`) — mais n'écoutaient pas
/// davantage les changements.
///
/// Ces trois règles sont sorties de la page parce qu'elles étaient écrites
/// DEUX fois (une pour les films, une pour les séries) et que c'est
/// exactement comme ça que les deux chemins avaient divergé.

/// Toutes les entrées d'un vivier qui appartiennent au même titre que [ref] :
/// les versions d'un film, les stubs et épisodes d'une série.
///
/// La règle de rapprochement est celle de l'accueil : clé de groupe insensible
/// à la casse (fusion cross-listes), plus le garde-fou **§homonymYear** — si le
/// titre ouvert porte une année, on ne ramasse que les entrées de la MÊME
/// année ou sans année, pour ne pas mélanger deux films homonymes d'époques
/// différentes (« Vengeance » 1990 et 2022).
List<M3uEntry> entriesOfTitle(Iterable<M3uEntry> pool, M3uEntry ref) {
  // Entrée synthétique (§tmdbOnlyDetails) : aucune source, rien à rapprocher.
  if (ref.url.isEmpty) return const <M3uEntry>[];
  final String key = contentGroupKey(ref);
  final String? year = ref.title.year;
  return pool
      .where((e) =>
          e.type == ref.type &&
          contentGroupKey(e) == key &&
          (year == null || e.title.year == null || e.title.year == year))
      .toList();
}

/// Empreinte comparable de ce que la mémoire contient pour un titre.
///
/// Elle sert à ne RIEN reconstruire quand un bump de version de la playlist ne
/// concerne pas la fiche ouverte — et il y en a beaucoup : un rechargement de
/// trois listes en produit au moins trois.
String versionsSignature(List<M3uEntry> entries) {
  final List<String> urls = entries.map((e) => e.url).toList()..sort();
  return '${urls.length}:${urls.join(' ')}';
}

/// La version à garder sélectionnée après un recalcul.
///
/// ⚠️ Garder la sélection courante si elle existe TOUJOURS : sinon la reprise
/// de lecture et le bouton LIRE sautent sous les doigts de l'utilisateur au
/// moment précis où une liste revient. Si elle a disparu (liste retirée,
/// source périmée), on retombe sur la première — jamais sur rien.
M3uEntry? keepSelection(List<M3uEntry> versions, String currentUrl) {
  if (versions.isEmpty) return null;
  for (final M3uEntry v in versions) {
    if (v.url == currentUrl) return v;
  }
  return versions.first;
}

// ── §22.1 — Les épisodes d'une série, réunis entre toutes les listes ─────────
//
// Une fiche de série rassemble des épisodes de DEUX origines : ceux qu'une
// liste M3U porte déjà (`Titre S01E02`, en mémoire) et ceux que la JSON API
// rend à la demande pour chaque stub (`/series/{user}/{pass}/{id}`). Ces règles
// étaient écrites dans la page, où rien ne les testait.

/// §22.1 — Au-delà de ce nombre de stubs pour UNE même liste, les suivants ne
/// sont pas interrogés : le panel n'accepte qu'une requête à la fois
/// (§hostGate), chaque stub de plus allonge l'attente de la fiche.
///
/// Mesuré sur les dumps réels (`test/series_merge_measure_test.dart`) : sous
/// les règles de [seriesStubsToFetch], un titre en garde au plus 7 sur une
/// liste (PLATINIUM, où chaque région est une série à part) ; ce plafond n'en
/// écarte que 12 sur 6 299.
const int kMaxSeriesStubsPerAccount = 6;

/// §22.1 — Ce qu'une pastille de version peut annoncer : qualité, langues,
/// libellé de version, marqueur du fournisseur.
///
/// Deux entrées de la MÊME liste qui partagent cette signature afficheraient la
/// même pastille : la fiche n'en garde qu'une (`dedupeVersions`, clé
/// libellé + liste). C'est aussi, mesuré, la forme des HOMONYMES d'une liste
/// (« Kingdom » / « Kingdom », « The Office. » / « The Office ») : deux
/// séries différentes que rien ne distingue dans leur nom.
String versionSignature(TitleMetadata t) => <String>[
      t.quality ?? '',
      t.languages.join('+'),
      t.versionLabel ?? '',
      t.providerTag ?? '',
    ].join('|');

String? _validTmdbId(String? id) {
  final String? v = id?.trim();
  return (v == null || v.isEmpty || v == '0') ? null : v;
}

/// La clé du NOM, sans l'alias TMDB (`contentGroupKey` l'applique, pas elle).
String _ownNameKey(M3uEntry e) => e.title.groupKey.isNotEmpty
    ? e.title.groupKey
    : TitleMetadata.computeGroupKey(e.displayName);

/// §22.1 — Les stubs de série dont la fiche doit aller chercher les épisodes,
/// dans l'ordre de [entries] (la liste de la vignette en tête).
///
/// **Le défaut réparé.** La fiche n'interrogeait qu'UN stub par liste
/// (`putIfAbsent(accountId)`) : quand une liste range les versions d'une série
/// en séries distinctes — « The Last of Us (4K) HDR » et « The Last of Us
/// (MULTI) FHD », « Pine Gap (HD) » et « Pine Gap (HD) (VOSTFR) » —, seule la
/// première rendait ses épisodes : la 4K ou la VOSTFR restaient
/// inatteignables depuis la fiche. Mesuré sur les dumps réels : 17,9 % des
/// titres de série chez PLATINIUM, 18,2 % chez xenoIptv, 3,2 % chez PREMIUM.
///
/// Règles, et pourquoi :
/// - le PREMIER stub de chaque liste est toujours interrogé : c'est la règle
///   d'avant, rien de ce qui s'affichait ne disparaît ;
/// - un stub de plus de la même liste ne l'est que s'il apporte une AUTRE
///   pastille ([versionSignature]) — une signature déjà vue ne peut rien
///   ajouter, et c'est la forme des homonymes : interroger « Kingdom » deux
///   fois mélangerait les saisons de deux séries sous une seule fiche ;
/// - avec la MÊME année que le premier (toutes deux absentes, ou égales) :
///   mesuré, « Koh-Lanta (FR) 2026 » à côté de « Koh-Lanta (FR) FHD » est une
///   AUTRE saison rangée comme une série, pas une autre version — ses épisodes
///   se seraient posés sur ceux de la première ;
/// - sous le MÊME nom, sauf si l'identifiant TMDB des deux est connu et égal
///   (« Ahsoka (4K) HDR » / « Star Wars : Ahsoka ») ;
/// - jamais si son identifiant TMDB contredit celui des stubs déjà retenus de
///   sa liste (« Charmed » 1998 / 2018, « Surface » 2005 / 2022 : mesuré) ;
/// - au plus [maxPerAccount] par liste.
///
/// ⚠️ Rien n'est filtré ENTRE listes : c'est le comportement d'avant, et une
/// garde TMDB entre fournisseurs retirerait une version dès que l'un d'eux
/// porte un identifiant faux.
///
/// Fonction pure : c'est elle qu'on teste.
List<M3uEntry> seriesStubsToFetch(
  Iterable<M3uEntry> entries, {
  int maxPerAccount = kMaxSeriesStubsPerAccount,
}) {
  final Set<String> urls = <String>{};
  final Map<String, List<M3uEntry>> kept = <String, List<M3uEntry>>{};
  final List<M3uEntry> out = <M3uEntry>[];
  for (final M3uEntry e in entries) {
    if (!isSeriesStubEntry(e) || !urls.add(e.url)) continue;
    final List<M3uEntry> mine = kept.putIfAbsent(e.accountId, () => []);
    if (mine.isNotEmpty && !_addsAVersion(e, mine, maxPerAccount)) continue;
    mine.add(e);
    out.add(e);
  }
  return out;
}

/// Un stub de plus pour une liste qui en a déjà ([mine], le premier en tête)
/// apporte-t-il une version, sans risque de mélanger deux séries ?
bool _addsAVersion(M3uEntry e, List<M3uEntry> mine, int maxPerAccount) {
  if (mine.length >= maxPerAccount) return false;
  final M3uEntry first = mine.first;
  if (e.title.year != first.title.year) return false;
  final String sig = versionSignature(e.title);
  if (mine.any((k) => versionSignature(k.title) == sig)) return false;
  String? ref;
  for (final M3uEntry k in mine) {
    ref ??= _validTmdbId(k.tmdbId);
  }
  final String? own = _validTmdbId(e.tmdbId);
  if (ref != null && own != null && own != ref) return false;
  return _ownNameKey(e) == _ownNameKey(first) || (own != null && own == ref);
}

/// §22.1 — Un épisode (saison + numéro) et TOUTES ses versions : listes,
/// qualités, langues. ⚠️ Jamais vide : un groupe naît de sa première version.
class EpisodeGroup {
  final int episodeNumber;
  final List<M3uEntry> versions;
  const EpisodeGroup(this.episodeNumber, this.versions);
  M3uEntry get best => versions.first;
}

/// §22.1 — Réunit des épisodes venus de partout en `saison → épisodes triés`,
/// chaque épisode portant ses versions : même saison + même numéro = UNE ligne,
/// quelle que soit la liste ou la voie (M3U en mémoire, JSON API d'un stub).
///
/// - Une même URL ne compte qu'une fois : la fiche re-fusionne ce qu'elle
///   affiche déjà avec ce qui arrive (relecture de la mémoire, nouvel appel).
/// - Les versions d'un épisode suivent [accountOrder] (la liste de la vignette
///   en tête, comme les versions d'un film), puis l'ordre d'arrivée. Sans ça,
///   l'ordre dépendait de la VOIE : les épisodes M3U passaient devant, quelle
///   que soit leur liste, et le résultat changeait selon ce qui répondait en
///   premier.
/// - [dedupe] retire les doublons de pastille (`dedupeVersions`) — injecté,
///   parce que le libellé lit la qualité MESURÉE (un service).
///
/// Fonction pure : c'est elle qu'on teste.
Map<int, List<EpisodeGroup>> mergeSeasonEpisodes(
  Iterable<M3uEntry> episodes, {
  required List<M3uEntry> Function(List<M3uEntry> versions) dedupe,
  List<String> accountOrder = const <String>[],
}) {
  final Map<String, int> rank = <String, int>{};
  for (final String id in accountOrder) {
    rank.putIfAbsent(id, () => rank.length);
  }
  final Set<String> seen = <String>{};
  final Map<int, Map<int, List<M3uEntry>>> bySeason = {};
  for (final M3uEntry ep in episodes) {
    final int? s = ep.title.seasonNumber;
    final int? n = ep.title.episodeNumber;
    if (s == null || n == null || !seen.add(ep.url)) continue;
    bySeason.putIfAbsent(s, () => {}).putIfAbsent(n, () => []).add(ep);
  }
  final List<int> seasons = bySeason.keys.toList()..sort();
  return <int, List<EpisodeGroup>>{
    for (final int s in seasons)
      s: <EpisodeGroup>[
        for (final int n in bySeason[s]!.keys.toList()..sort())
          EpisodeGroup(n, dedupe(_byAccountRank(bySeason[s]![n]!, rank))),
      ],
  };
}

/// Tri STABLE par rang de liste (`List.sort` ne garantit pas la stabilité) :
/// deux versions d'une même liste gardent leur ordre d'arrivée.
List<M3uEntry> _byAccountRank(List<M3uEntry> versions, Map<String, int> rank) {
  if (rank.isEmpty || versions.length < 2) return versions;
  final int unknown = rank.length;
  final List<(int, M3uEntry)> indexed = <(int, M3uEntry)>[
    for (int i = 0; i < versions.length; i++) (i, versions[i]),
  ];
  indexed.sort((a, b) {
    final int c = (rank[a.$2.accountId] ?? unknown)
        .compareTo(rank[b.$2.accountId] ?? unknown);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return <M3uEntry>[for (final (int, M3uEntry) p in indexed) p.$2];
}

/// §22.1 / §autoNextEp — La version de l'épisode suivant qui PROLONGE
/// [current] : même liste et même signature d'abord, même liste ensuite, sinon
/// la première. `null` seulement si [versions] est vide.
///
/// **Le défaut réparé.** L'épisode suivant prenait toujours la PREMIÈRE version
/// de son groupe : dès qu'un épisode existe dans deux listes (ou en 4K et en
/// HD dans la même), l'enchaînement pouvait changer de fournisseur, de langue
/// ou de qualité en plein visionnage — le VF devenait VOSTFR à l'épisode
/// suivant.
///
/// Fonction pure : c'est elle qu'on teste.
M3uEntry? continuationVersion(List<M3uEntry> versions, M3uEntry current) {
  if (versions.isEmpty) return null;
  final String sig = versionSignature(current.title);
  M3uEntry? sameList;
  for (final M3uEntry v in versions) {
    if (v.accountId != current.accountId) continue;
    if (versionSignature(v.title) == sig) return v;
    sameList ??= v;
  }
  return sameList ?? versions.first;
}

/// §22.1 — L'épisode que l'appelant a DEMANDÉ en ouvrant la fiche, ou `null`
/// quand [entry] n'est que la TÊTE d'un groupe de l'accueil.
///
/// **Le défaut réparé.** L'accueil ouvre une série avec `versions.first`, et
/// la tête d'un groupe n'est pas un choix : pour une liste M3U c'est un
/// épisode quelconque, pour un groupe mixte (stub + épisodes, 27,76 % des
/// séries mesurées, R45) elle dépend de l'ORDRE D'AJOUT des comptes. La fiche
/// la prenait pour une demande explicite : elle s'ouvrait sur cet épisode-là,
/// et la reprise en cours (§seriesFavCard) n'était jamais proposée.
///
/// Demande explicite = [entry] est un épisode, et aucune version passée avec
/// lui n'est un AUTRE épisode (un stub ne dit rien de l'épisode voulu).
///
/// Fonction pure : c'est elle qu'on teste.
({int season, int episode})? requestedEpisodeOf(
  M3uEntry entry,
  Iterable<M3uEntry> versions,
) {
  final int? s = entry.title.seasonNumber;
  final int? n = entry.title.episodeNumber;
  if (s == null || n == null) return null;
  for (final M3uEntry v in versions) {
    final int? vs = v.title.seasonNumber;
    final int? vn = v.title.episodeNumber;
    if (vs == null || vn == null) continue;
    if (vs != s || vn != n) return null;
  }
  return (season: s, episode: n);
}
