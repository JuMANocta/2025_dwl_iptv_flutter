import '../../data/models/m3u_entry.dart';
import '../search/m3u_filter.dart'
    show contentGroupKey, dedupeTvVersions, tvGroupKey;

/// §searchAllNames (2026-09-25) — Une recherche trouve un titre RÉUNI par le
/// nom de N'IMPORTE LAQUELLE de ses versions, et montre la vignette réunie
/// entière. **Pure** — testée (`test/search_groups_test.dart`).
///
/// **Le manque.** Les doublons d'un même film sont réunis sous une seule clé
/// (`contentGroupKey` → `TmdbGroupAliasService.canonical`) : « Le Roi Scorpion
/// 2 » et « Scorpion King 2 » ne font qu'UNE vignette sur l'accueil. La
/// recherche, elle, ne gardait dans chaque groupe que les versions dont le
/// TITRE correspondait : taper le nom anglais rendait bien une seule carte,
/// mais une carte tronquée — sans la version française, donc sans son
/// affiche, sa langue ni sa reprise.
///
/// **La règle.** 1ʳᵉ passe : les clés des groupes qui ont au moins une version
/// trouvée (ordre des résultats inchangé : celui de la première trouvée).
/// 2ᵉ passe, si [complete] : TOUTES les entrées de ces clés, dans l'ordre du
/// catalogue — le même groupe, et la même tête, que la vignette de l'accueil.
/// Le coût est une recherche de clé par entrée, sur une passe déjà mémorisée
/// par requête (§searchMemo).
List<List<M3uEntry>> searchHitGroups(
  Iterable<M3uEntry> entries, {
  required bool Function(M3uEntry entry) matches,
  required String Function(M3uEntry entry) keyOf,
  bool complete = true,
}) {
  final Map<String, List<M3uEntry>> byKey = <String, List<M3uEntry>>{};
  for (final M3uEntry e in entries) {
    if (!matches(e)) continue;
    (byKey[keyOf(e)] ??= <M3uEntry>[]).add(e);
  }
  if (!complete || byKey.isEmpty) return byKey.values.toList();
  final Map<String, List<M3uEntry>> full = <String, List<M3uEntry>>{
    for (final String k in byKey.keys) k: <M3uEntry>[],
  };
  for (final M3uEntry e in entries) {
    full[keyOf(e)]?.add(e);
  }
  return full.values.toList();
}

/// §searchAllNames — Les groupes de la recherche de l'accueil pour [type]
/// ([q] déjà en minuscules), AVANT le partage par année (§homonymYear, fait
/// par l'accueil). Films et séries : groupes complets par la clé de fusion ;
/// chaînes : clé de chaîne et dédoublonnage de qualité, comme avant (une
/// chaîne n'a pas de titre traduit).
List<List<M3uEntry>> homeSearchGroups(
  List<M3uEntry> entries,
  String q,
  M3uContentType type,
) {
  // §searchAccents — La requête est repliée une seule fois, et confrontée à
  // `groupKey`, qui est PRÉ-CALCULÉ et lui aussi sans accents.
  final String qFolded = TitleMetadata.foldAccents(q);
  bool match(M3uEntry e) =>
      e.title.groupKey.contains(qFolded) ||
      e.displayName.toLowerCase().contains(q) ||
      e.rawTitle.toLowerCase().contains(q);

  if (type == M3uContentType.tv) {
    return <List<M3uEntry>>[
      for (final List<M3uEntry> g in searchHitGroups(entries,
          matches: match,
          keyOf: (M3uEntry e) => tvGroupKey(e.displayName),
          complete: false))
        dedupeTvVersions(g),
    ];
  }
  // §23 — contentGroupKey est insensible à la casse (fusion cross-listes).
  return searchHitGroups(entries, matches: match, keyOf: contentGroupKey);
}
