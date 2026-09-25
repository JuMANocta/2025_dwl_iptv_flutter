import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

/// Service de gestion des favoris (§1d).
///
/// **Modèle** : un favori est identifié par une clé canonique de la forme
/// `"<type>|<groupKey>"` :
///   - `movie|Inception`
///   - `series|Breaking Bad`
///   - `tv|TF1`
///
/// `groupKey` est le `displayName` pour films/séries (= clé de regroupement
/// cross-comptes) et `tvGroupKey(displayName)` pour les chaînes (normalise les
/// suffixes de qualité).
///
/// **Stockage** :
///   - `SharedPreferences` clé `"favorites_v1"` → `List<String>` JSON
///   - Cache mémoire `_cache` chargé au premier accès
///   - `version` (`ValueNotifier<int>`) incrémenté à chaque modif → permet
///     aux widgets `ValueListenableBuilder` de se rebuilder
///
/// **API** : tout est statique. Pas d'injection, pas de DI — cohérent avec le
/// reste de l'app (`PlaylistService`, `ParsedPlaylistService`…).
class FavoritesService {
  static const String _prefsKey = 'favorites_v1';

  static final Set<String> _cache = <String>{};
  static bool _loaded = false;

  /// Bumpe à chaque modification — écouter via `ValueListenableBuilder`.
  static final ValueNotifier<int> version = ValueNotifier(0);

  // ── Génération des clés canoniques ──────────────────────────────────────

  /// Clé canonique pour une entrée M3U (cross-comptes, indépendante de la variante).
  /// §23 — films/séries via [contentGroupKey] (minuscules) pour suivre la
  /// fusion cross-listes insensible à la casse. TV inchangé (tvGroupKey).
  /// §favYear — FILMS **et SÉRIES** incluent l'année (`movie|titre|année`,
  /// `series|titre|année`) pour ne pas mélanger les homonymes/remakes (cohérent
  /// avec §homonymYear des carrousels). TV inchangé (tvGroupKey).
  static String keyFor(M3uEntry e) {
    if (e.type == M3uContentType.tv) {
      return keyForGroup(e.type, tvGroupKey(e.displayName));
    }
    // movie | series : type|titre|année
    final t = e.type == M3uContentType.movie ? 'movie' : 'series';
    return '$t|${contentGroupKey(e)}|${e.title.year ?? ''}';
  }

  /// §favYear — Ancienne clé SANS année (`movie|titre` / `series|titre`), telle
  /// que stockée avant 2026-06-11. Conservée pour la rétro-compat : un favori
  /// legacy continue d'allumer le cœur (cf. [isEntryFavorite]) jusqu'à ce que
  /// l'utilisateur le re-toggle (qui le nettoie via [toggleEntry]).
  static String _legacyKey(M3uEntry e) {
    final t = e.type == M3uContentType.movie ? 'movie' : 'series';
    return '$t|${contentGroupKey(e)}';
  }

  /// §favPersistFix — Normalise une clé de favori **stockée** vers la forme
  /// canonique courante `type|groupKey[|année]`.
  ///
  /// Migration §23b : `groupKey` repassé en minuscules + ponctuation normalisée
  /// (`computeGroupKey`) pour les anciennes clés movie/series.
  ///
  /// ⚠️ Correctif persistance : l'ancienne version normalisait **tout** ce qui
  /// suit le 1er `|`, transformant `series|titre|2008` → `series|titre 2008`
  /// (le séparateur d'année `|` devenait une espace). La clé ne correspondait
  /// alors plus à [keyFor] → le favori « disparaissait » à chaque redémarrage,
  /// re-corrompu puis re-persisté. On isole désormais le **suffixe d'année** et
  /// on ne normalise QUE le `groupKey` → opération idempotente sur une clé saine.
  @visibleForTesting
  static String normalizeStoredKey(String key) {
    if (!key.startsWith('movie|') && !key.startsWith('series|')) return key;
    final firstSep = key.indexOf('|');
    final type = key.substring(0, firstSep);
    var body = key.substring(firstSep + 1); // groupKey[|année]
    String yearSuffix = '';
    // §favYear — l'année (chiffres ou vide) est le segment après le DERNIER `|`.
    final lastSep = body.lastIndexOf('|');
    if (lastSep >= 0) {
      final tail = body.substring(lastSep + 1);
      if (RegExp(r'^\d{0,4}$').hasMatch(tail)) {
        yearSuffix = '|$tail';
        body = body.substring(0, lastSep);
      }
    }
    return '$type|${TitleMetadata.computeGroupKey(body)}$yearSuffix';
  }

  // ── R53 + §aliasByPoster — Les favoris suivent la table d'alias ──────────
  //
  // La clé d'un favori de film ou de série passe par `contentGroupKey`, donc
  // par la table d'alias (`TmdbGroupAliasService`). Cette table est refaite à
  // CHAQUE chargement et déchargement de liste (§lazyUnload) : qu'un alias
  // apparaisse, et la clé de la variante devient celle de la canonique ; qu'il
  // disparaisse, et c'est l'inverse. Le favori restait stocké sous l'ancienne
  // clé et plus rien ne le retrouvait (R53, prouvé par
  // `test/favorites_alias_test.dart`). La réconciliation §favReconcile ne
  // tourne qu'une fois par schéma : elle ne pouvait pas le voir.
  //
  // Le correctif : après chaque reconstruction de la table, chaque favori est
  // COMPLÉTÉ par ses équivalents (la canonique et toutes ses variantes, même
  // type, même année). On ajoute, on ne remplace jamais : la clé d'une
  // variante doit survivre au jour où l'alias disparaît. Pur, idempotent, sans
  // bump de schéma.

  /// Le suffixe d'année d'une clé stockée : chiffres (ou rien) après le
  /// DERNIER `|` — même convention que [normalizeStoredKey].
  static final RegExp _reYearTail = RegExp(r'^\d{0,4}$');

  /// (type, clé de groupe, suffixe d'année — `|2023`, `|` ou `''` pour une clé
  /// héritée) d'une clé de film ou de série ; `null` pour une chaîne.
  static (String, String, String)? _splitKey(String key) {
    if (!key.startsWith('movie|') && !key.startsWith('series|')) return null;
    final int first = key.indexOf('|');
    final String type = key.substring(0, first);
    String body = key.substring(first + 1);
    String suffix = '';
    final int last = body.lastIndexOf('|');
    if (last >= 0 && _reYearTail.hasMatch(body.substring(last + 1))) {
      suffix = body.substring(last);
      body = body.substring(0, last);
    }
    return (type, body, suffix);
  }

  static Map<String, Set<String>> _variantsOf(Map<String, String> alias) {
    final Map<String, Set<String>> out = <String, Set<String>>{};
    alias.forEach((v, c) => (out[c] ??= <String>{}).add(v));
    return out;
  }

  /// Les clés équivalentes à [key] sous [alias] ([key] compris) : la
  /// canonique et toutes ses variantes, même type, même suffixe d'année.
  static Set<String> _equivalents(String key, Map<String, String> alias,
      Map<String, Set<String>> variantsOf) {
    final (String, String, String)? parts = _splitKey(key);
    if (parts == null) return <String>{key};
    final (String type, String body, String suffix) = parts;
    final String c = alias[body] ?? body;
    return <String>{
      key,
      '$type|$c$suffix',
      for (final String v in variantsOf[c] ?? const <String>{})
        '$type|$v$suffix',
    };
  }

  /// R53 — Les clés à AJOUTER à [stored] pour qu'aucun favori ne s'éteigne
  /// sous la table [alias] : pour chaque favori, sa canonique et toutes ses
  /// variantes. Vide quand rien ne manque — donc idempotent.
  ///
  /// Fonction PURE : c'est elle qu'on teste.
  @visibleForTesting
  static Set<String> aliasClosureAdditions(
      Iterable<String> stored, Map<String, String> alias) {
    if (alias.isEmpty) return const <String>{};
    final Map<String, Set<String>> variantsOf = _variantsOf(alias);
    final Set<String> have =
        stored is Set<String> ? stored : stored.toSet();
    final Set<String> out = <String>{};
    for (final String k in have) {
      for (final String e in _equivalents(k, alias, variantsOf)) {
        if (!have.contains(e)) out.add(e);
      }
    }
    return out;
  }

  static bool _aliasListening = false;

  /// R53 — Appelé à chaque reconstruction de la table d'alias.
  static void _applyAliasClosure() {
    if (!_loaded) return;
    final Set<String> add =
        aliasClosureAdditions(_cache, TmdbGroupAliasService.aliases);
    if (add.isEmpty) return;
    _cache.addAll(add);
    version.value++;
    unawaited(_persist());
    debugPrint('⭐ FavoritesService R53 : ${add.length} clé(s) équivalente(s) ajoutée(s) (titres réunis par alias TMDB)');
  }

  // ── §favReconcile — Réconciliation post-changement de parsing ────────────
  //
  // Les clés canoniques descendent de `TitleMetadata.baseTitle`. Quand la
  // sortie du parsing change (correctifs regex → bump `ParsedPlaylist.
  // schemaVersion`), les clés persistées AVANT le changement ne matchent plus
  // `keyFor` recalculé sur le nouveau baseTitle → favoris « fantômes » (cœur
  // éteint, titre absent de la rangée Favoris, mais la clé traîne en base).
  // Vécu au bump 11→12 (§parseAudit2026-06-30 : préfixes `|XX|` casse mixte
  // strippés, pipes résiduels supprimés `CORP|US| CHRISTI`→`CORPUS CHRISTI`,
  // exposants ᴴ²⁶⁵ normalisés).
  //
  // On ne peut pas transformer l'ancienne clé par manipulation de chaîne
  // seule (impossible de savoir quel espace de `corp us christi` était un
  // pipe) → on RAPPROCHE chaque clé orpheline des clés actuelles de la
  // playlist en mémoire via une forme « squash » (groupKey sans espaces).

  /// Forme compacte d'un corps de clé : normalisation groupKey puis retrait
  /// des espaces → insensible aux découpages (`corp us christi` et
  /// `corpus christi` → `corpuschristi`).
  static String _squash(String s) =>
      TitleMetadata.computeGroupKey(s).replaceAll(' ', '');

  /// Revue 2026-09-11, D1A-05 — Les mots que le parsing EFFAÇAIT partout du
  /// titre jusqu'au schéma 19 (`_reLangTags` de `TitleMetadata`). Au schéma 20
  /// ils restent quand ils font partie du titre (« The French Dispatch »,
  /// « Empire of Light », « Les Arnaqueurs VIP ») : les clés s'ALLONGENT, et le
  /// mot est souvent au MILIEU — deux choses que le fuzzy préfixe/suffixe ne
  /// sait pas suivre (il rapproche une clé stockée d'un candidat plus COURT).
  ///
  /// ⚠️ Liste HISTORIQUE, figée : c'est ce que l'ANCIEN parseur retirait, pas
  /// ce que le parseur actuel juge ambigu. Ne pas la synchroniser.
  ///
  /// ⚠️ `\b` ASCII et casse libre VOLONTAIREMENT, comme l'ancienne regex : elle
  /// coupait aussi dans les mots accentués (« Vipère au poing » → « ère au
  /// poing »), et c'est cette clé-là qui est stockée. Appliquée au titre NON
  /// replié (`baseTitle`), avant `computeGroupKey`, comme le faisait le parseur.
  static final _reSchema19Erased = RegExp(
      r'\b(?:VIP|RAW|FRENCH|SUBS?|AUDIO|LEGENDADO|LEGENDA|LEG|LIGHT)\b',
      caseSensitive: false);

  /// Squash de [title] privé des mots de [_reSchema19Erased] : la clé
  /// qu'aurait produite le parsing du schéma 19 pour le même titre.
  static String _squashSchema19(String title) =>
      _squash(title.replaceAll(_reSchema19Erased, ' '));

  /// Enregistre la forme « schéma 19 » de [title] dans [reduced][bucket].
  /// La valeur est `(squash complet, clé)`. Deux titres DIFFÉRENTS pour une même
  /// forme → marquée ambiguë (`('', '')`) : on ne choisit pas entre « French
  /// Girl » et « Girl Light » de la même année. Deux clés du MÊME titre à la
  /// casse près (`tv|Blacked Raw` / `tv|BLACKED RAW`, les clés de chaînes
  /// gardent la casse) ne sont pas une ambiguïté : le dernier gagne, comme dans
  /// l'index principal.
  static void _addSchema19Form(
      Map<String, Map<String, (String, String)>> reduced,
      String bucket,
      String title,
      String key) {
    final full = _squash(title);
    final r = _squashSchema19(title);
    if (r.isEmpty || r == full) return; // aucun mot concerné
    final m = reduced[bucket] ??= {};
    final prev = m[r];
    m[r] = (prev == null || prev.$1 == full) ? (full, key) : ('', '');
  }

  /// §favReconcile — Calcule les ré-appariements `ancienneClé → nouvelleClé`
  /// des favoris orphelins (stockés mais ne correspondant plus à aucune entrée
  /// de la playlist). Fonction PURE (aucun état, aucune I/O) → testable.
  ///
  /// Règles d'appariement (même type, même segment année pour movie/series ;
  /// clé legacy sans année ↔ index sans année) :
  ///   1. Égalité squash exacte (corruption pipes reconstituée).
  ///   2. Fuzzy borné : le squash candidat est préfixe OU suffixe du squash
  ///      stocké (ancien garbage de préfixe `|FR-4k|` ou de suffixe ᴴ²⁶⁵).
  ///      Garde-fous : candidat ≥ 4 chars ET ≥ moitié du stocké ; plusieurs
  ///      candidats → le plus long gagne ; égalité de longueur → on ne touche
  ///      pas (ambigu).
  ///   3. Aucun match → clé conservée telle quelle (jamais de suppression).
  ///
  /// [unresolvedOut] (optionnel) reçoit les clés orphelines restées sans
  /// appariement — pour le log récapitulatif.
  @visibleForTesting
  static Map<String, String> reconcileKeys(
    Set<String> storedKeys,
    List<M3uEntry> entries, {
    Set<String>? unresolvedOut,
  }) {
    if (storedKeys.isEmpty || entries.isEmpty) return const {};

    // 1. Clés valides aujourd'hui (+ formes legacy movie/series) et index de
    //    rapprochement `type[#année]` → { squash(groupKey) → clé canonique }.
    final validKeys = <String>{};
    final index = <String, Map<String, String>>{};
    // Revue 2026-09-11, D1A-05 — même découpage, forme « schéma 19 ».
    final schema19 = <String, Map<String, (String, String)>>{};
    for (final e in entries) {
      final key = keyFor(e);
      if (!validKeys.add(key)) continue; // autre version du même groupe
      if (e.type == M3uContentType.tv) {
        final body = key.substring(3);
        (index['tv'] ??= {})[_squash(body)] = key;
        _addSchema19Form(schema19, 'tv', body, key);
      } else {
        validKeys.add(_legacyKey(e));
        final t = e.type == M3uContentType.movie ? 'movie' : 'series';
        final squash = _squash(contentGroupKey(e));
        (index['$t#${e.title.year ?? ''}'] ??= {})[squash] = key;
        // Une clé legacy stockée (sans année) doit pouvoir migrer vers la
        // clé canonique AVEC année → bucket sans année en parallèle.
        (index[t] ??= {})[squash] = key;
        // Le titre NON replié : l'ancienne regex coupait dans « Vipère ».
        final title = e.title.baseTitle;
        _addSchema19Form(schema19, '$t#${e.title.year ?? ''}', title, key);
        _addSchema19Form(schema19, t, title, key);
      }
    }

    // 2. Appariement des orphelines.
    final rewrites = <String, String>{};
    for (final stored in storedKeys) {
      if (validKeys.contains(stored)) continue;

      // Décompose type / corps / année (même convention que normalizeStoredKey).
      String bucket;
      String body;
      if (stored.startsWith('tv|')) {
        bucket = 'tv';
        body = stored.substring(3);
      } else if (stored.startsWith('movie|') || stored.startsWith('series|')) {
        final type = stored.substring(0, stored.indexOf('|'));
        body = stored.substring(type.length + 1);
        bucket = type; // legacy sans année par défaut
        var yearSuffix = '';
        final lastSep = body.lastIndexOf('|');
        if (lastSep >= 0) {
          final tail = body.substring(lastSep + 1);
          if (RegExp(r'^\d{0,4}$').hasMatch(tail)) {
            bucket = '$type#$tail';
            yearSuffix = '|$tail';
            body = body.substring(0, lastSep);
          }
        }
        // R53 — Une VARIANTE d'alias (clé ajoutée par [aliasClosureAdditions])
        // n'est pas une orpheline : sa canonique est valide. La « réparer » par
        // le fuzzy la remplacerait par un autre titre et effacerait la clé qui
        // garde le favori le jour où l'alias disparaît.
        final String canon = TmdbGroupAliasService.canonical(body);
        if (canon != body && validKeys.contains('$type|$canon$yearSuffix')) {
          continue;
        }
      } else {
        continue; // clé inconnue → intouchée
      }

      final candidates = index[bucket];
      final storedSquash = _squash(body);
      if (candidates == null || storedSquash.isEmpty) {
        unresolvedOut?.add(stored);
        continue;
      }

      // Règle 1 : égalité squash exacte.
      final exact = candidates[storedSquash];
      if (exact != null) {
        if (exact != stored) rewrites[stored] = exact;
        continue;
      }

      // Règle 1 bis (revue 2026-09-11, D1A-05) : la clé stockée est celle
      // qu'aurait produite le schéma 19 pour UN SEUL candidat du bucket (même
      // type, même année). Forme partagée → règle 2, comme avant.
      final viaSchema19 = schema19[bucket]?[storedSquash]?.$2;
      if (viaSchema19 != null && viaSchema19.isNotEmpty) {
        rewrites[stored] = viaSchema19;
        continue;
      }

      // Règle 2 : fuzzy borné préfixe/suffixe, le plus long gagne.
      String? bestKey;
      var bestLen = 0;
      var ambiguous = false;
      for (final cand in candidates.entries) {
        final sq = cand.key;
        if (sq.length < 4 || sq.length * 2 < storedSquash.length) continue;
        if (!storedSquash.startsWith(sq) && !storedSquash.endsWith(sq)) {
          continue;
        }
        if (sq.length > bestLen) {
          bestLen = sq.length;
          bestKey = cand.value;
          ambiguous = false;
        } else if (sq.length == bestLen && cand.value != bestKey) {
          ambiguous = true;
        }
      }
      if (bestKey != null && !ambiguous) {
        rewrites[stored] = bestKey;
      } else {
        unresolvedOut?.add(stored);
      }
    }
    return rewrites;
  }

  /// §favReconcile — Flag one-shot lié au schéma de cache : les clés ne
  /// peuvent dériver QUE quand la sortie du parsing change (= bump schéma).
  /// Une fois la réconciliation faite pour ce schéma, no-op à chaque boot
  /// (pas de scan des ~centaines de milliers d'entrées pour rien).
  static const String _reconcileFlag =
      'favorites_reconciled_schema_${ParsedPlaylist.schemaVersion}';

  /// Nom du flag one-shot — exposé pour les tests de non-régression (§favAudit).
  @visibleForTesting
  static String get reconcileFlagKey => _reconcileFlag;

  /// Remet le service à zéro entre deux tests (état statique partagé).
  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _loaded = false;
    _running = null;
  }

  /// Passe en cours, pour sérialiser les appels concurrents (§favAudit).
  static Future<void>? _running;

  /// §favReconcile — Ré-apparie les favoris orphelins contre la playlist en
  /// mémoire ([ParsedPlaylistService.entries]). À appeler quand la playlist
  /// est chargée (boot) ; [finalPass] pose le flag one-shot — ne le passer à
  /// true que quand TOUS les comptes sont en mémoire (un favori peut n'exister
  /// que sur un compte secondaire hydraté en différé).
  ///
  /// §favAudit — L'ancienne garde `if (_reconciling) return;` faisait
  /// silencieusement ABANDONNER la passe appelante. Quand c'était la passe
  /// FINALE (multi-comptes : 1re passe fire & forget au boot, finale en fin
  /// d'hydratation), le **flag one-shot n'était jamais posé** → scan complet
  /// de la playlist à CHAQUE démarrage. On sérialise désormais : une passe
  /// intermédiaire redondante est bien sautée, mais la finale attend son tour.
  static Future<void> reconcileWithPlaylist({bool finalPass = false}) async {
    final running = _running;
    if (running != null) {
      if (!finalPass) return; // passe intermédiaire déjà couverte
      await running;
    }
    final pass = _reconcilePass(finalPass: finalPass);
    _running = pass;
    try {
      await pass;
    } finally {
      if (identical(_running, pass)) _running = null;
    }
  }

  static Future<void> _reconcilePass({required bool finalPass}) async {
    try {
      await _ensureLoaded();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_reconcileFlag) ?? false) return;

      // Aucun favori → rien ne peut avoir dérivé. Le flag est quand même posé
      // (les favoris créés ensuite le seront avec le parsing courant), sinon
      // on rescannerait la playlist à chaque boot pour rien.
      if (_cache.isEmpty) {
        if (finalPass) await prefs.setBool(_reconcileFlag, true);
        return;
      }

      // Playlist pas encore en mémoire : on ne peut RIEN réconcilier, donc on
      // ne pose surtout pas le flag (sinon des orphelins resteraient à vie).
      final entries = ParsedPlaylistService.entries;
      if (entries.isEmpty) return;

      final unresolved = <String>{};
      final rewrites =
          reconcileKeys(Set.of(_cache), entries, unresolvedOut: unresolved);
      if (rewrites.isNotEmpty) {
        for (final r in rewrites.entries) {
          _cache.remove(r.key);
          _cache.add(r.value);
        }
        version.value++;
        await _persist();
      }
      if (rewrites.isNotEmpty || unresolved.isNotEmpty) {
        debugPrint('🔄 FavoritesService §favReconcile : '
            '${rewrites.length} favori(s) migré(s), '
            '${unresolved.length} non résolu(s)');
      }
      if (finalPass) await prefs.setBool(_reconcileFlag, true);
    } catch (e) {
      debugPrint('❌ FavoritesService: réconciliation échouée — $e');
    }
  }

  /// Clé canonique pour un groupe (type + clé de regroupement).
  static String keyForGroup(M3uContentType type, String groupKey) {
    final t = switch (type) {
      M3uContentType.movie  => 'movie',
      M3uContentType.series => 'series',
      M3uContentType.tv     => 'tv',
    };
    return '$t|$groupKey';
  }

  // ── Chargement / persistence ────────────────────────────────────────────

  /// Charge le cache depuis `SharedPreferences` (idempotent).
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<String>();
        // §23b — Migration one-shot : les clés movie/series étaient stockées
        // avec la casse + ponctuation d'origine du displayName ; la clé
        // canonique est désormais `TitleMetadata.computeGroupKey` (minuscules
        // + ponctuation → espace, alignée sur la fusion cross-listes).
        // On migre à la lecture pour ne perdre aucun favori existant.
        var migrated = false;
        for (final key in list) {
          final normalized = normalizeStoredKey(key);
          if (normalized != key) migrated = true;
          _cache.add(normalized);
        }
        if (migrated) {
          debugPrint('🔄 FavoritesService: clés migrées en minuscules (§23)');
          _persist(); // fire & forget
        }
      }
    } catch (e) {
      debugPrint('❌ FavoritesService: erreur chargement — $e');
    }
    _loaded = true;
    // R53 — La table a pu être construite avant le chargement des favoris ;
    // ensuite, chaque reconstruction complète les favoris.
    if (!_aliasListening) {
      _aliasListening = true;
      TmdbGroupAliasService.version.addListener(_applyAliasClosure);
    }
    _applyAliasClosure();
  }

  /// Sauvegarde le cache dans `SharedPreferences` (fire & forget côté UI).
  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache.toList()));
    } catch (e) {
      debugPrint('❌ FavoritesService: erreur persistence — $e');
    }
  }

  // ── API publique ────────────────────────────────────────────────────────

  /// Initialise le service au démarrage de l'app (à appeler dans `main()`).
  /// Sans appel explicite, le cache se charge à la première lecture/écriture.
  static Future<void> init() => _ensureLoaded();

  /// Snapshot synchrone du jeu de favoris. Vide si non encore chargé.
  static Set<String> get all => Set.unmodifiable(_cache);

  /// Vrai si la clé est marquée comme favori.
  static bool isFavorite(String key) => _cache.contains(key);

  /// Vrai si l'entrée M3U correspond à un favori.
  /// §favYear — Pour un FILM/SÉRIE, on accepte AUSSI l'ancienne clé sans année
  /// (favori legacy) → le cœur reste allumé après mise à jour de l'app.
  static bool isEntryFavorite(M3uEntry e) {
    if (e.type != M3uContentType.tv) {
      return _cache.contains(keyFor(e)) || _cache.contains(_legacyKey(e));
    }
    return isFavorite(keyFor(e));
  }

  /// §favYear — Toggle/ajout/retrait À PARTIR DE L'ENTRÉE (recommandé pour les
  /// films) : gère la clé avec année ET nettoie l'éventuelle clé legacy au
  /// retrait. Retourne le nouvel état (`true` = ajouté).
  static Future<bool> toggleEntry(M3uEntry e) async {
    await _ensureLoaded();
    if (isEntryFavorite(e)) {
      await _removeEntry(e);
      return false;
    }
    await add(keyFor(e));
    return true;
  }

  /// Ajoute un favori depuis l'entrée (clé avec année pour les films).
  static Future<void> addEntry(M3uEntry e) => add(keyFor(e));

  static Future<void> _removeEntry(M3uEntry e) async {
    await _ensureLoaded();
    // Retire la clé courante ET la legacy (films/séries) en une notification.
    // R53 — et tous leurs équivalents d'alias : sinon une variante gardée
    // rallumerait le cœur de la vignette réunie qu'on vient d'éteindre.
    final Map<String, String> alias = TmdbGroupAliasService.aliases;
    final Map<String, Set<String>> variantsOf = _variantsOf(alias);
    final Set<String> keys = _equivalents(keyFor(e), alias, variantsOf);
    if (e.type != M3uContentType.tv) {
      keys.addAll(_equivalents(_legacyKey(e), alias, variantsOf));
    }
    var removed = false;
    for (final String k in keys) {
      if (_cache.remove(k)) removed = true;
    }
    if (removed) {
      version.value++;
      await _persist();
    }
  }

  /// Ajoute un favori. Idempotent.
  static Future<void> add(String key) async {
    await _ensureLoaded();
    if (_cache.add(key)) {
      // R53 — complété tout de suite : si l'alias disparaît avant la
      // prochaine reconstruction, la variante garde le favori.
      _cache.addAll(
          aliasClosureAdditions(<String>[key], TmdbGroupAliasService.aliases));
      version.value++;
      await _persist();
      debugPrint('⭐ FavoritesService: ajout — $key');
    }
  }

  /// Vide tous les favoris (action destructive, utilisée pour reset/debug).
  static Future<void> clear() async {
    if (_cache.isEmpty) return;
    _cache.clear();
    version.value++;
    await _persist();
  }

  /// Remplace l'intégralité des favoris en une seule opération.
  /// Utilisé par le BackupService (§10) pour l'import. Une seule notification
  /// `version++` + un seul persist, contrairement à clear()+add()×N.
  static Future<void> replaceAll(Iterable<String> keys) async {
    await _ensureLoaded();
    _cache
      ..clear()
      ..addAll(keys);
    // R53 — une sauvegarde d'avant la réunion des titres : complétée aussi.
    _cache.addAll(aliasClosureAdditions(_cache, TmdbGroupAliasService.aliases));
    version.value++;
    await _persist();
    // §favReconcile — Un backup .aether peut contenir des clés générées par
    // une version antérieure du parsing → on ré-arme le flag puis on tente la
    // réconciliation immédiatement (no-op silencieux si playlist pas chargée :
    // le prochain boot s'en chargera, le flag étant effacé).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_reconcileFlag);
    } catch (_) {}
    reconcileWithPlaylist(finalPass: true); // fire & forget
  }
}
