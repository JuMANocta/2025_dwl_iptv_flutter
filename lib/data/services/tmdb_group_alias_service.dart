import 'package:flutter/foundation.dart';

import '../models/m3u_entry.dart';

/// §tmdbMerge — Réunit sous une seule vignette les copies d'un même film dont
/// les fournisseurs n'écrivent pas le titre dans la même langue.
///
/// **Le cas signalé.** Le corpus contient `100 Mètres` (VOD, PREMIUM, XENO) et
/// `100 METERS` (PLATINIUM, PREMIUM) : le **même film**, en français et en
/// anglais. Leurs clés de regroupement sont `100 metres` et `100 meters` —
/// aucune normalisation de chaîne ne peut ni ne doit les rapprocher (le repli
/// d'accents donne `metres` d'un côté, `meters` de l'autre). Seul l'identifiant
/// TMDB, que les panels fournissent, dit qu'il s'agit d'une seule œuvre.
///
/// **Ce que ça couvre — et ce que ça ne couvre pas.** Mesuré le 2026-08-30 :
/// PLATINIUM porte l'identifiant sur 93 % de ses films (champ `tmdb_id`),
/// PREMIUM sur 99 % (champ `tmdb`, cf. §tmdbField). VOD et XENO n'en ont
/// **aucun**. La fusion joue donc entre les deux premières listes, et les
/// copies des deux autres restent à part. C'est une amélioration partielle,
/// assumée : mieux vaut réunir ce qu'on peut prouver que deviner le reste.
///
/// **§aliasByPoster (lot 9, 2026-09-25) — ce que l'identifiant ne couvre pas,
/// l'AFFICHE le couvre.** VOD, XENO et PREMIUM pointent vers
/// `image.tmdb.org/t/p/<taille>/<fichier>` (92 à 99 % des entrées) ; un
/// fichier d'affiche appartient à UNE œuvre TMDB. Deux clés qui partagent un
/// fichier sont réunies, sans un seul appel réseau — sous quatre gardes, cf.
/// `_posterPass`. Mesuré sur les six dumps (`tmdb_alias_measure_test.dart`) :
/// voir `decisions.md` §aliasByPoster.
///
/// ⚠️ **Garde-fou sur l'année.** Un identifiant fournisseur peut être faux —
/// c'est de la donnée saisie par un tiers. Deux titres ne sont fusionnés que
/// si leurs années sont compatibles (identiques, ou inconnues). Sans ce
/// contrôle, une seule coquille dans un catalogue fusionne deux films
/// différents, et l'utilisateur n'a AUCUN moyen de comprendre pourquoi.
///
/// ⛔ **La table change à chaque chargement ET déchargement de liste**
/// (§lazyUnload) : une clé de favori (`type|clé canonique|année`) bouge avec
/// elle. `FavoritesService` complète ses favoris par leurs équivalents après
/// chaque reconstruction (R53) — ne jamais retirer cet écouteur.
abstract final class TmdbGroupAliasService {
  /// `clé variante` → `clé canonique`. Vide tant que rien n'est chargé.
  static Map<String, String> _alias = const <String, String>{};

  /// Bumpé à chaque reconstruction — les vues qui mémoïsent leur regroupement
  /// doivent l'inclure dans leur clé de cache, comme `ParsedPlaylistService`.
  /// `FavoritesService` s'y abonne aussi (R53).
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static int get aliasCount => _alias.length;

  /// §aliasByPoster — Combien de clés la seule affiche a réunies (mesure).
  static int get posterAliasCount => _posterAliases;
  static int _posterAliases = 0;

  /// La table entière (`variante → canonique`), en lecture : c'est elle qui
  /// dit à `FavoritesService` quelles clés sont équivalentes.
  static Map<String, String> get aliases => _alias;

  /// Clé canonique d'un groupe. Retourne [key] tel quel si aucune fusion ne
  /// s'applique — c'est le cas de l'immense majorité des titres.
  static String canonical(String key) => _alias[key] ?? key;

  /// Les variantes réunies sous [canonicalKey] (vide si aucune). Table inverse
  /// calculée au premier appel après chaque reconstruction.
  ///
  /// §aliasByPoster — `InferredCategoryService` s'en sert : une catégorie
  /// apprise sous la clé d'une variante doit rester trouvable quand la
  /// vignette réunie prend une autre clé.
  static Set<String> variantsOf(String canonicalKey) {
    final Map<String, Set<String>> inv = _inverse ??= () {
      final Map<String, Set<String>> m = <String, Set<String>>{};
      _alias.forEach((v, c) => (m[c] ??= <String>{}).add(v));
      return m;
    }();
    return inv[canonicalKey] ?? const <String>{};
  }

  static Map<String, Set<String>>? _inverse;

  /// Mesure seulement (`tmdb_alias_measure_test.dart`) : la table SANS la
  /// passe des affiches, pour comparer avant / après sur les mêmes listes.
  @visibleForTesting
  static bool posterPassEnabled = true;

  /// §aliasByPoster (2) — Au-delà de 3 titres sur une affiche, un FILM n'est
  /// réuni que sous la garde stricte (même année écrite des deux côtés, mêmes
  /// numéros) et jusqu'à ce nombre de titres ; au-delà, l'affiche est
  /// générique. Réglable pour la mesure seulement (3 = l'ancienne garde).
  @visibleForTesting
  static int crowdedFilmMax = 8;

  @visibleForTesting
  static void resetForTest() {
    _alias = const <String, String>{};
    _inverse = null;
    _posterAliases = 0;
    version.value++;
  }

  /// Reconstruit la table depuis TOUTES les entrées chargées.
  ///
  /// ⚠️ Doit voir **tous les comptes à la fois** : une fusion cross-listes ne
  /// peut pas se déduire d'un catalogue isolé.
  static void rebuild(Iterable<M3uEntry> entries) {
    // Mesure (thread UI, à chaque chargement de liste) : le journal le dit, en
    // release aussi — c'est le seul chiffre AOT qu'on aura du téléviseur.
    final Stopwatch sw = Stopwatch()..start();
    // (type, tmdbId) → clé de groupe → nombre d'entrées
    final byId = <String, Map<String, int>>{};
    // (type, tmdbId) → années rencontrées (hors null)
    final years = <String, Set<String>>{};
    // §aliasByPoster — (type, fichier d'affiche TMDB) → les clés qui le
    // portent. Le reste (poids, années, identifiants) n'est relevé qu'en
    // seconde lecture, pour les SEULES clés concernées : la reconstruction
    // tourne sur le thread UI à chaque chargement de liste.
    //
    // ⚠️ Mesuré (426 000 entrées, JIT) : un ensemble PAR affiche et une clé
    // `type|fichier` construite par entrée coûtaient ~120 ms de plus — la
    // plupart des affiches n'ont qu'une clé. On garde la première clé vue, et
    // un ensemble seulement quand une seconde apparaît.
    final firstMovie = <String, String>{}, firstSeries = <String, String>{};
    final multiMovie = <String, Set<String>>{};
    final multiSeries = <String, Set<String>>{};

    for (final e in entries) {
      if (e.type == M3uContentType.tv) continue; // pas de TMDB pour les chaînes
      final key = e.title.groupKey;
      if (key.isEmpty) continue;
      if (posterPassEnabled) {
        final String? poster = tmdbPosterFile(e.logoUrl);
        if (poster != null) {
          final bool movie = e.type == M3uContentType.movie;
          final Map<String, String> first = movie ? firstMovie : firstSeries;
          final String? prev = first[poster];
          if (prev == null) {
            first[poster] = key;
          } else if (prev != key) {
            ((movie ? multiMovie : multiSeries)[poster] ??= <String>{prev})
                .add(key);
          }
        }
      }
      final id = e.tmdbId;
      if (id == null || id.isEmpty || id == '0') continue;
      final y = e.title.year;
      final bucket = '${e.type.name}|$id';
      (byId[bucket] ??= <String, int>{}).update(key, (n) => n + 1,
          ifAbsent: () => 1);
      if (y != null) (years[bucket] ??= <String>{}).add(y);
    }

    final alias = <String, String>{};
    for (final entry in byId.entries) {
      final variants = entry.value;
      if (variants.length < 2) continue; // rien à réunir
      // ⚠️ Années divergentes → identifiant douteux, on s'abstient.
      if ((years[entry.key]?.length ?? 0) > 1) continue;
      // Canonique = la forme la plus répandue ; à égalité, la plus petite dans
      // l'ordre alphabétique — pour que la table soit STABLE d'un lancement à
      // l'autre (sinon les favoris dériveraient à chaque démarrage).
      final ordered = variants.keys.toList()
        ..sort((a, b) {
          final c = variants[b]!.compareTo(variants[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
      final canonicalKey = ordered.first;
      for (final k in ordered.skip(1)) {
        alias[k] = canonicalKey;
      }
    }

    // ⚠️ Chaînage : si A→B et B→C existaient, une clé pourrait pointer sur une
    // variante au lieu de la canonique. On aplatit en une passe.
    final flat = <String, String>{};
    alias.forEach((k, v) {
      var target = v;
      var hops = 0;
      while (alias.containsKey(target) && hops++ < 8) {
        target = alias[target]!;
      }
      if (target != k) flat[k] = target;
    });

    final int byIdCount = flat.length;
    final int msFirst = sw.elapsedMilliseconds;
    final _PosterStats stats = !posterPassEnabled
        ? (_PosterStats()..alias = flat)
        : _posterPass(
            entries: entries,
            byPoster: <M3uContentType, Map<String, Set<String>>>{
              M3uContentType.movie: multiMovie,
              M3uContentType.series: multiSeries,
            },
            idAlias: flat,
          );
    _alias = stats.alias;
    _inverse = null;
    _posterAliases = _alias.length - byIdCount;
    version.value++;
    debugPrint('🔗 §tmdbMerge — $byIdCount clés fusionnées par identifiant TMDB (${byId.length} identifiants vus) ; §aliasByPoster — $_posterAliases de plus par affiche (écartées : ${stats.years} années, ${stats.crowded} affiches à plus de 3 titres, ${stats.parts} numéros de partie, ${stats.ids} identifiants contradictoires) ; $msFirst ms + ${sw.elapsedMilliseconds - msFirst} ms');
  }

  /// §aliasByPoster — La seconde passe : réunit, PAR-DESSUS la table des
  /// identifiants ([idAlias]), les groupes dont les entrées partagent un même
  /// fichier d'affiche TMDB.
  ///
  /// Quatre gardes, chacune née d'un faux positif MESURÉ sur les dumps :
  /// 1. **années compatibles** (une seule année connue au plus) — « The Lion
  ///    King » 1994 et « Le Roi Lion » 2019 partagent une affiche ;
  /// 2. **au plus 3 titres par affiche** — une affiche générique réunissait
  ///    « Gangster's Paradise 1 » à « 5 » ;
  /// 3. **même numéro de partie** ([partSignature]) — « Norman… 1 » et
  ///    « … 2 », « Der Mordanschlag Teil 1 » et « Teil 2 » : une affiche pour
  ///    deux films ;
  /// 4. **pas d'identifiants fournisseur contradictoires** — si les deux
  ///    groupes portent chacun un identifiant et qu'ils diffèrent, c'est le
  ///    fournisseur qui a raison contre l'affiche.
  ///
  /// Les gardes se jugent sur les groupes ENTIERS (union-find) : deux fusions
  /// permises chacune ne doivent pas, en chaîne, réunir 2019 et 2021.
  ///
  /// Canonique d'une fusion = celle du groupe le plus LOURD (le plus
  /// d'entrées), à égalité la plus petite alphabétiquement : un groupe réuni
  /// par identifiant garde sa canonique dès qu'il domine, et la table reste
  /// stable d'un lancement à l'autre (buckets parcourus dans l'ordre).
  static _PosterStats _posterPass({
    required Iterable<M3uEntry> entries,
    required Map<M3uContentType, Map<String, Set<String>>> byPoster,
    required Map<String, String> idAlias,
  }) {
    final _PosterStats stats = _PosterStats()..alias = idAlias;
    String idCanon(String k) => idAlias[k] ?? k;

    // 1. Les affiches qui réunissent 2 ou 3 groupes. Au-delà :
    //    - une SÉRIE, jamais (« on reste découpé » : les éditions de
    //      Koh-Lanta, Bleach Kai et Bleach TYBW partagent leurs affiches) ;
    //    - un FILM, jusqu'à [crowdedFilmMax] titres, sous la garde STRICTE :
    //      mesuré, un film populaire vit sous 4 noms dans 4 listes (« The
    //      Godfather: Part III », « Le Parrain, 3e partie », « … - The
    //      Godfather III » et, sur la même affiche, l'Épilogue de 2020) —
    //      c'est justement le cas à réunir, sans l'Épilogue.
    final List<(List<String>, bool)> candidates = <(List<String>, bool)>[];
    // Parcours dans un ordre FIXE (type, puis fichier) : la table doit être
    // la même d'un lancement à l'autre.
    for (final M3uContentType t in <M3uContentType>[
      M3uContentType.movie,
      M3uContentType.series,
    ]) {
      for (final String f in byPoster[t]!.keys.toList()..sort()) {
        final List<String> canon =
            ({for (final k in byPoster[t]![f]!) idCanon(k)}.toList()..sort());
        if (canon.length < 2) continue; // déjà un seul groupe
        final bool strict = canon.length > 3;
        if (strict &&
            (t != M3uContentType.movie || canon.length > crowdedFilmMax)) {
          stats.crowded++;
          continue;
        }
        candidates.add((canon, strict));
      }
    }
    if (candidates.isEmpty) return stats;

    // 2. Les groupes concernés, et leurs clés brutes (variantes comprises).
    final Map<String, Set<String>> members = <String, Set<String>>{
      for (final (List<String> c, bool _) in candidates)
        for (final String k in c) k: <String>{k},
    };
    idAlias.forEach((v, c) => members[c]?.add(v));
    final Map<String, String> rawToGroup = <String, String>{
      for (final MapEntry<String, Set<String>> m in members.entries)
        for (final String r in m.value) r: m.key,
    };

    // 3. Seconde lecture, pour ces seules clés : poids, années, identifiants.
    final gWeight = <String, int>{};
    final gYears = <String, Set<String>>{};
    final gIds = <String, Set<String>>{};
    for (final e in entries) {
      if (e.type == M3uContentType.tv) continue;
      final String? g = rawToGroup[e.title.groupKey];
      if (g == null) continue;
      gWeight.update(g, (n) => n + 1, ifAbsent: () => 1);
      final y = e.title.year;
      if (y != null) (gYears[g] ??= <String>{}).add(y);
      final id = e.tmdbId;
      if (id != null && id.isNotEmpty && id != '0') {
        (gIds[g] ??= <String>{}).add(id);
      }
    }
    final gParts = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> m in members.entries)
        m.key: {for (final String r in m.value) partSignature(r)},
    };

    // 4. Union-find : les gardes se jugent sur les groupes ENTIERS.
    final parent = <String, String>{for (final k in members.keys) k: k};
    String find(String k) {
      var r = k;
      while (parent[r] != r) {
        r = parent[r]!;
      }
      var c = k;
      while (parent[c] != r) {
        final next = parent[c]!;
        parent[c] = r;
        c = next;
      }
      return r;
    }

    for (final (List<String> canon, bool strict) in candidates) {
      String root = find(canon.first);
      for (final c in canon.skip(1)) {
        final String other = find(c);
        if (other == root) continue;
        final Set<String> ys = {...?gYears[root], ...?gYears[other]};
        // Garde stricte (affiche à plus de 3 titres) : l'année doit être
        // ÉCRITE des deux côtés — une absence n'est plus une compatibilité.
        if (ys.length > 1 ||
            (strict &&
                ((gYears[root]?.isEmpty ?? true) ||
                    (gYears[other]?.isEmpty ?? true)))) {
          stats.years++;
          continue;
        }
        final Set<String> pr = gParts[root]!, po = gParts[other]!;
        if (pr.length != 1 || po.length != 1 || pr.first != po.first) {
          stats.parts++;
          continue;
        }
        final Set<String> ids = {...?gIds[root], ...?gIds[other]};
        if (ids.length > 1) {
          stats.ids++;
          continue;
        }
        // Le plus lourd garde sa canonique ; à égalité, l'ordre alphabétique.
        final int wr = gWeight[root] ?? 0, wo = gWeight[other] ?? 0;
        final bool keepRoot = wr > wo || (wr == wo && root.compareTo(other) < 0);
        final String winner = keepRoot ? root : other;
        final String loser = keepRoot ? other : root;
        parent[loser] = winner;
        gYears[winner] = ys;
        gIds[winner] = ids;
        gWeight[winner] = wr + wo;
        root = winner;
      }
    }

    // 5. Table finale : la table des identifiants, dont les groupes réunis
    // pointent désormais vers leur racine.
    final Map<String, String> out = Map<String, String>.of(idAlias);
    for (final MapEntry<String, Set<String>> m in members.entries) {
      final String root = find(m.key);
      if (root == m.key) continue;
      for (final String raw in m.value) {
        if (raw != root) out[raw] = root;
      }
    }
    // Une ancienne racine d'identifiant devenue variante : ses variantes
    // pointent déjà vers la nouvelle racine (étape 5), rien ne reste chaîné.
    stats.alias = out;
    return stats;
  }
}

class _PosterStats {
  Map<String, String> alias = const <String, String>{};
  int years = 0;
  int crowded = 0;
  int parts = 0;
  int ids = 0;
}

/// §aliasByPoster — Le fichier d'une affiche TMDB
/// (`https://image.tmdb.org/t/p/w600_and_h900_bestv2/abc123.jpg` → `abc123.jpg`),
/// quelle que soit la taille demandée ; `null` pour toute autre image.
///
/// ⚠️ Seul l'hôte `image.tmdb.org` compte : un fichier hébergé ailleurs ne
/// prouve rien sur l'œuvre. Ni regex ni recherche dans toute l'URL : la
/// fonction passe sur chaque entrée de chaque liste à chaque chargement
/// (~430 000 sur les dumps) ; l'hôte se teste à sa place (`http://` ou
/// `https://`).
///
/// Fonction pure : c'est elle qu'on teste.
String? tmdbPosterFile(String? url) {
  const String marker = 'image.tmdb.org/t/p/';
  // ⚠️ `startsWith(…, index)` LÈVE si l'index dépasse la chaîne : un logo
  // vide ou tronqué ne doit pas faire tomber la reconstruction.
  if (url == null || url.length < 8 + marker.length) return null;
  final int at = url.startsWith(marker, 8)
      ? 8
      : (url.startsWith(marker, 7) ? 7 : -1);
  if (at < 0) return null;
  final int slash = url.lastIndexOf('/');
  // `…/t/p/<taille>/<fichier>` : un segment de taille entre les deux.
  if (slash <= at + marker.length) return null;
  final String file = url.substring(slash + 1);
  // Les fichiers TMDB font une trentaine de caractères : en dessous de dix,
  // ce n'est pas l'identifiant d'une image.
  if (file.lastIndexOf('.') < 10) return null;
  return file;
}

/// §aliasByPoster — Les NUMÉROS d'une clé de groupe, triés : `« … teil 1 »` →
/// `1`, `« 22 11 63 »` → `11,22,63`, `« … part two »` → `2`, aucun → `''`.
///
/// Deux titres qui partagent une affiche mais pas leurs numéros ne sont PAS
/// la même œuvre (« Norman… 1 » / « … 2 », mesuré) — et un numéro présent
/// d'un seul côté non plus : « Underworld 2 : Évolution » et « Underworld :
/// Evolution » ne se réuniront pas par l'affiche. La prudence coûte quelques
/// fusions justes ; l'imprudence mélangerait deux films sous une vignette.
///
/// Comptent : les nombres, les chiffres romains de II à IX (pas I, V ni X,
/// qui sont aussi des mots : « I, Robot », « V pour Vendetta », « X-Men »), et
/// un nombre écrit en lettres juste après un mot de partie (« part one »).
///
/// Fonction pure : c'est elle qu'on teste.
String partSignature(String groupKey) {
  final List<String> tokens = groupKey.split(' ');
  // Tout nombre, même collé à des lettres : « مرضي ودحام ج2 » (ج = partie,
  // mesuré), « code geass r2 ». Lecture à la main, sans regex (mesuré : 4 µs
  // par titre en JIT avec `allMatches`, la passe en lit des milliers).
  // ⚠️ `tryParse` : un numéro de 20 chiffres (référence de fournisseur) ne
  // doit pas faire lever la reconstruction.
  final Set<int> numbers = <int>{};
  int start = -1;
  for (int i = 0; i <= groupKey.length; i++) {
    final int c = i < groupKey.length ? groupKey.codeUnitAt(i) : 0;
    final bool digit = c >= 0x30 && c <= 0x39;
    if (digit && start < 0) start = i;
    if (!digit && start >= 0) {
      numbers.add(int.tryParse(groupKey.substring(start, i)) ?? -1);
      start = -1;
    }
  }
  for (int i = 0; i < tokens.length; i++) {
    final String t = tokens[i];
    final int? roman = _romans[t];
    if (roman != null) {
      numbers.add(roman);
      continue;
    }
    if (_partWords.contains(t) && i + 1 < tokens.length) {
      final int? w = _numberWords[tokens[i + 1]];
      if (w != null) numbers.add(w);
    }
  }
  return (numbers.toList()..sort()).join(',');
}

const Map<String, int> _romans = <String, int>{
  'ii': 2, 'iii': 3, 'iv': 4, 'vi': 6, 'vii': 7, 'viii': 8, 'ix': 9,
};

const Set<String> _partWords = <String>{
  'part', 'partie', 'parte', 'teil', 'chapter', 'chapitre', 'capitulo',
  'volume', 'vol', 'tome', 'livre', 'book',
};

const Map<String, int> _numberWords = <String, int>{
  'one': 1, 'two': 2, 'three': 3, 'four': 4,
  'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4,
  'uno': 1, 'dos': 2, 'tres': 3,
  'um': 1, 'dois': 2,
  'eins': 1, 'zwei': 2, 'drei': 3,
};
