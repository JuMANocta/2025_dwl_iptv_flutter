import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetherStream/core/utils/string_pool.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'tmdb_group_alias_service.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';
import 'package:aetherStream/data/services/hidden_regions_service.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'load_failure.dart';

/// État de chargement d'un compte IPTV en mémoire (§16).
///
/// Permet à l'UI (chips dans `_AccountTile`) d'afficher l'état réel de
/// disponibilité de chaque playlist : en cours de téléchargement, en cours
/// de parsing, chargée et prête, ou en erreur (réseau, fichier corrompu…).
enum AccountLoadState {
  /// Aucune tentative de chargement (état initial).
  notLoaded,
  /// Téléchargement du .m3u en cours.
  downloading,
  /// .m3u téléchargé, parsing isolate en cours.
  parsing,
  /// Playlist chargée en mémoire, disponible pour la home/recherche.
  loaded,
  /// Échec (réseau, fichier corrompu, schéma obsolète).
  error,
}

/// Hub central des playlists parsées.
///
/// Cycle de vie :
///   1. [loadActive] — démarrage, compte actif uniquement (cache disque ou parse complet)
///   2. [preloadOthersFromDisk] — background silencieux, autres comptes depuis disque uniquement
///   3. [entries] — accès synchrone à toutes les entrées disponibles en mémoire
///   4. [markStale] — appelé par PlaylistService après téléchargement d'une
///      nouvelle SOURCE : la copie en mémoire est périmée, le cache disque RESTE
///   5. [forget] — suppression d'un compte / schéma obsolète : mémoire ET disque
class ParsedPlaylistService {
  // ── Mémoire — persiste toute la session app ───────────────────────────────
  static final Map<String, ParsedPlaylist> _memory = {};

  /// §reloadScope — Listes dont la SOURCE a été renouvelée mais dont la copie
  /// en mémoire date encore de l'ancienne.
  ///
  /// **Ce que ça remplace.** [markStale] retirait la liste de la mémoire. Le
  /// but était bon (forcer la ré-analyse) mais l'effet de bord ne l'était pas :
  /// pendant tout le re-parse — plusieurs dizaines de secondes sur un gros
  /// catalogue — la liste ACTIVE disparaissait de l'accueil, de la recherche et
  /// des fiches, alors que [reloadFromDisk] est justement écrit pour faire un
  /// échange atomique « sans laisser d'état vide ». Avec deux listes, ça se
  /// voyait comme « je n'ai plus qu'une liste » à chaque rechargement.
  ///
  /// Le drapeau dit la même chose sans rien casser : la copie reste
  /// AFFICHABLE, mais tout ce qui décide « faut-il (ré)analyser ? » la traite
  /// comme absente ([loadActive], [loadSecondary], [preloadOthersFromDisk],
  /// `PlaylistFleetService._factsFor`, `main._hydrateInBoot`).
  static final Set<String> _stale = <String>{};

  /// Vrai si la copie en mémoire de ce compte est périmée (cf. [_stale]).
  static bool isStale(String accountId) => _stale.contains(accountId);

  /// §reloadScope — Nombre de listes CONFIGURÉES, publié par ceux qui les
  /// listent déjà (boot, réconciliateur, page Comptes).
  ///
  /// ⚠️ Ne jamais déduire ça de [_memory] : c'est exactement le défaut corrigé.
  /// `isMultiAccount` répondait « une seule liste » dès qu'il n'en restait
  /// qu'une EN MÉMOIRE, et la fiche se mettait alors à fusionner les versions
  /// de même libellé et à masquer le nom des listes — pendant un rechargement,
  /// un déchargement, ou tant qu'une liste n'était pas revenue.
  static int _configuredAccounts = 0;

  static void reportConfiguredAccounts(int count) {
    if (count == _configuredAccounts || count < 0) return;
    _configuredAccounts = count;
  }
  /// accountId → label affiché (ex: "Provider FR") — pour les badges multi-comptes.
  static final Map<String, String> _accountNames = {};
  /// Bumpe à chaque fois qu'une playlist est ajoutée/retirée de [_memory].
  /// Les widgets qui font [entries] peuvent écouter ce notifier pour se rebuilder.
  static final ValueNotifier<int> version = ValueNotifier(0);
  /// §16 — État de chargement par compte. ValueListenableBuilder pour les
  /// chips dans `_AccountTile` (PRINCIPAL / DISPONIBLE / EN COURS / ERREUR).
  static final ValueNotifier<Map<String, AccountLoadState>> loadStates =
      ValueNotifier<Map<String, AccountLoadState>>({});

  /// §lazyUnload — Timestamp du dernier accès en lecture par compte. Utilisé
  /// par [unloadIdleSecondaries] pour décharger de mémoire les comptes
  /// secondaires qui n'ont pas été consultés depuis longtemps (M3U + cache
  /// JSON.gz restent sur disque → rechargement ~50 ms si re-demandés).
  static final Map<String, DateTime> _lastAccess = {};

  /// Marque un compte comme "accédé récemment" → reset son délai d'idle.
  /// Appelé automatiquement par tous les accesseurs ([entries],
  /// [entriesWithPriority], [byTypeWithPriority], [getAccount]).
  static void markAccessed(String accountId) {
    _lastAccess[accountId] = DateTime.now();
  }

  static void _touchAllLoaded() {
    final now = DateTime.now();
    for (final id in _memory.keys) {
      _lastAccess[id] = now;
    }
  }

  /// §fleetState — POURQUOI une liste n'est pas en mémoire.
  ///
  /// Vit **à côté** de [loadStates], qui ne dit que l'état : les 5 valeurs de
  /// `AccountLoadState` pilotent déjà les chips à quatre endroits, et une
  /// migration complète coûterait plus cher qu'elle ne rapporte.
  static final ValueNotifier<Map<String, LoadFailure>> loadFailures =
      ValueNotifier<Map<String, LoadFailure>>({});

  /// Raison courante de l'absence d'une liste — `null` quand tout va bien.
  static LoadFailure? failureOf(String accountId) =>
      loadFailures.value[accountId];

  /// Marque l'état d'un compte et notifie les listeners (immutable copy).
  ///
  /// §fleetState — Trois changements par rapport à la version d'origine :
  ///
  ///   1. **La clé n'est PLUS supprimée sur `notLoaded`.** C'est ce `remove`
  ///      qui rendait « jamais tenté », « déchargé pour libérer la mémoire » et
  ///      « ré-analyse avortée » rigoureusement indiscernables : dans les trois
  ///      cas la lecture retombait sur le défaut de [stateOf], et rien ne
  ///      permettait de distinguer un fonctionnement voulu d'une panne.
  ///   2. **[kind] / [detail] alimentent [loadFailures]**, le registre des
  ///      raisons (cf. `load_failure.dart`).
  ///   3. **Chaque transition est journalisée** (ancien → nouveau + raison) :
  ///      la disparition d'une liste ne laissait jusqu'ici AUCUNE trace.
  ///
  /// ⚠️ Conséquence à connaître : `loadStates.value.length` compte désormais
  /// tous les comptes VUS au moins une fois, et non plus seulement ceux dans un
  /// état différent de `notLoaded`. Tout lecteur qui s'en sert comme
  /// DÉNOMINATEUR doit être revu.
  static void setLoadState(
    String accountId,
    AccountLoadState state, {
    LoadFailureKind? kind,
    String? detail,
  }) {
    final AccountLoadState? previous = loadStates.value[accountId];

    // §reloadScope — Une liste déclarée « chargée » n'est plus périmée. Le
    // drapeau se lève ICI parce que tous les chemins de chargement passent par
    // cet appel : aucun ne peut l'oublier.
    if (state == AccountLoadState.loaded) _stale.remove(accountId);

    // Le registre des raisons ne vit que pour les états « pas en mémoire ».
    final LoadFailureKind? resolved = switch (state) {
      AccountLoadState.notLoaded => kind ?? LoadFailureKind.never,
      // Sans précision, un `error` vient des chemins réseau de `_hydrateOne` ;
      // les échecs d'analyse passent tous `kind: parse` explicitement.
      AccountLoadState.error => kind ?? LoadFailureKind.network,
      _ => null,
    };

    // ⚠️ Les raisons d'ABORD : un listener de `loadStates` doit voir un
    // registre déjà cohérent avec le nouvel état, pas celui d'avant.
    final failures = Map<String, LoadFailure>.from(loadFailures.value);
    if (resolved == null) {
      failures.remove(accountId);
    } else {
      failures[accountId] =
          LoadFailure(resolved, detail: detail, at: DateTime.now());
    }
    loadFailures.value = failures;

    final next = Map<String, AccountLoadState>.from(loadStates.value);
    next[accountId] = state;
    loadStates.value = next;

    if (previous != state || resolved != null) {
      final String why = resolved == null
          ? ''
          : ' · ${resolved.name}'
              '${(detail == null || detail.isEmpty) ? '' : ' — $detail'}';
      debugPrint('🔁 §fleetState $accountId : '
          '${previous?.name ?? 'inconnu'} → ${state.name}$why');
    }
  }

  /// Lecture sync d'un état (utile pour les checks rapides sans rebuild).
  static AccountLoadState stateOf(String accountId) =>
      loadStates.value[accountId] ?? AccountLoadState.notLoaded;

  /// §23 — Route vers le bon parser selon le type de fichier source :
  ///   - `.json` → [XtreamCatalogParser] (catalogue JSON direct player_api,
  ///     isolate, métadonnées riches)
  ///   - `.m3u` (ou autre) → [M3uParser] (texte M3U, regex — fallback get.php)
  static Future<void> _parsePlaylistFile(
    String path,
    List<M3uEntry> films,
    List<M3uEntry> series,
    List<M3uEntry> tv, {
    required String accountId,
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) {
    // §langFilter — set des régions masquées passé aux parsers (filtre au
    // parse → entrées masquées jamais stockées). Lu sur le main thread ici puis
    // copié dans l'isolate.
    final hidden = HiddenRegionsService.hidden;
    if (path.toLowerCase().endsWith('.json')) {
      return XtreamCatalogParser.parseFile(path, films, series, tv,
          accountId: accountId,
          onProgress: onProgress,
          onDetail: onDetail,
          hidden: hidden);
    }
    return M3uParser.parseFile(path, films, series, tv,
        accountId: accountId,
        onProgress: onProgress,
        onDetail: onDetail,
        hidden: hidden);
  }

  // ── API publique ───────────────────────────────────────────────────────────

  /// Charge le compte actif.
  /// - Cache mémoire → retour immédiat.
  /// - Cache disque valide → ~50ms.
  /// - Sinon → parse complet + sauvegarde disque (fire & forget).
  static Future<ParsedPlaylist> loadActive(
    String accountId,
    String accountName,
    String m3uPath, {
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) async {
    // 1. Déjà en mémoire — et pas périmée (§reloadScope).
    if (_memory.containsKey(accountId) && !isStale(accountId)) {
      _accountNames[accountId] = accountName;
      setLoadState(accountId, AccountLoadState.loaded);
      onProgress?.call(1.0);
      debugPrint('⚡ ParsedPlaylist: déjà en mémoire — $accountName');
      return _memory[accountId]!;
    }

    // 2. Cache disque valide
    final disk = await _loadFromDisk(
      accountId,
      m3uPath,
      onProgress: onProgress,
      onDetail: onDetail,
    );
    if (disk != null) {
      debugPrint('✅ ParsedPlaylist: cache disque chargé — $accountName (${disk.entries.length} entrées)');
      _auditCategories(accountName, disk.entries);
      _memory[accountId] = disk;
      _accountNames[accountId] = accountName;
      setLoadState(accountId, AccountLoadState.loaded);
      onProgress?.call(1.0);
      _bumpAfterLoad();
      return disk;
    }

    // 3. Parse complet du fichier .m3u
    debugPrint('🔍 ParsedPlaylist: parse complet — $accountName');
    setLoadState(accountId, AccountLoadState.parsing);
    final films   = <M3uEntry>[];
    final series  = <M3uEntry>[];
    final tv      = <M3uEntry>[];
    try {
      await _parsePlaylistFile(
        m3uPath, films, series, tv,
        accountId: accountId,
        onProgress: onProgress,
        onDetail: onDetail,
      );
    } catch (e) {
      debugPrint('❌ ParsedPlaylist.loadActive — parse échoué : $e');
      setLoadState(accountId, AccountLoadState.error,
          kind: LoadFailureKind.parse, detail: describeError(e));
      rethrow;
    }

    final allEntries = [...films, ...series, ...tv];
    final m3uModified = await File(m3uPath).lastModified();
    final playlist = ParsedPlaylist(
      accountId:    accountId,
      schema:       ParsedPlaylist.schemaVersion,
      m3uModifiedAt: m3uModified,
      entries:      allEntries,
    );

    _memory[accountId] = playlist;
    _accountNames[accountId] = accountName;
    setLoadState(accountId, AccountLoadState.loaded);
    _bumpAfterLoad();

    // Sauvegarde disque en arrière-plan (non bloquant)
    _saveToDisk(accountId, playlist);

    debugPrint('✅ ParsedPlaylist: parse terminé — ${allEntries.length} entrées');
    return playlist;
  }

  /// Précharge les autres comptes depuis le disque uniquement (background silencieux).
  /// N'effectue aucun téléchargement réseau — ignore les comptes sans cache disque.
  static Future<void> preloadOthersFromDisk(List<StreamAccount> accounts) async {
    for (final acc in accounts) {
      if (_memory.containsKey(acc.id) && !isStale(acc.id)) continue;
      // §23 — Résolution du fichier source (même convention que
      // PlaylistService.pathForAccountId, dupliquée ici pour éviter un import
      // circulaire) : catalogue .json prioritaire, sinon .m3u legacy.
      final dir = await getApplicationDocumentsDirectory();
      var m3uPath = '${dir.path}/playlist_${acc.id}.json';
      if (!File(m3uPath).existsSync()) {
        m3uPath = '${dir.path}/playlist_${acc.id}.m3u';
      }
      if (!File(m3uPath).existsSync()) {
        // §cacheKeep — Ce `continue` était MUET : un compte sans aucun fichier
        // source disparaissait de l'accueil sans une ligne de journal.
        //
        // ⚠️ On ne touche PAS à son état ici : une hydratation peut être en
        // train de le télécharger en parallèle, et l'écraser en « non chargé »
        // ferait mentir le décompte de la barre du haut.
        debugPrint('ℹ️ §cacheKeep préchargement : aucun fichier source pour '
            '« ${acc.label} » (ni .json ni .m3u) → ignoré');
        continue;
      }

      final disk = await _loadFromDisk(acc.id, m3uPath);
      if (disk != null) {
        _memory[acc.id] = disk;
        _accountNames[acc.id] = acc.label;
        setLoadState(acc.id, AccountLoadState.loaded);
        debugPrint('✅ ParsedPlaylist: préchargé depuis disque — ${acc.label} (${disk.entries.length} entrées)');
        _auditCategories(acc.label, disk.entries);
        _bumpAfterLoad();
      } else {
        // §cacheKeep — LE cas qui rendait le défaut invisible : la source est
        // là, le cache analysé non (supprimé trop tôt, tronqué, schéma
        // obsolète). La liste reste absente de `_memory`, donc absente de
        // l'accueil ET de la recherche — et jusqu'ici, personne ne le disait.
        //
        // ⚠️ Cette méthode NE DOIT PAS se mettre à analyser : elle tourne en
        // arrière-plan pendant que l'accueil s'affiche. C'est au réconciliateur
        // de reprendre le travail ; ici on se contente de NOMMER le problème.
        setLoadState(acc.id, AccountLoadState.notLoaded,
            kind: LoadFailureKind.cacheGone,
            detail: 'source présente, cache analysé inexploitable');
        debugPrint('⚠️ §cacheKeep préchargement : « ${acc.label} » a une source '
            'sur disque mais AUCUN cache analysé exploitable → invisible de '
            'l\'accueil tant que rien ne la ré-analyse');
      }
    }
  }

  /// Charge un compte secondaire en mémoire (depuis le cache disque ou
  /// re-parsing du M3U). Idempotent : si déjà chargé, sort immédiatement.
  /// Utilisé par la routine d'agrégation multi-comptes pour rendre toutes
  /// les playlists disponibles à la recherche et à la home.
  ///
  /// §bootHydrate — [onProgress]/[onDetail] ne servent que lorsque ce
  /// chargement est fait **pendant le démarrage**, où il devient une étape
  /// annoncée. En arrière-plan (le cas historique), les deux restent nuls et
  /// la méthode est silencieuse comme avant.
  static Future<void> loadSecondary(
    String accountId,
    String accountName,
    String m3uPath, {
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) async {
    if (_memory.containsKey(accountId) && !isStale(accountId)) {
      _accountNames[accountId] = accountName;
      setLoadState(accountId, AccountLoadState.loaded);
      return;
    }
    // Tentative cache disque
    final disk = await _loadFromDisk(
      accountId,
      m3uPath,
      onProgress: onProgress,
      onDetail: onDetail,
    );
    if (disk != null) {
      _memory[accountId] = disk;
      _accountNames[accountId] = accountName;
      setLoadState(accountId, AccountLoadState.loaded);
      _bumpAfterLoad();
      debugPrint('✅ ParsedPlaylist secondaire: cache disque — $accountName');
      return;
    }
    // Sinon parse complet
    setLoadState(accountId, AccountLoadState.parsing);
    final films  = <M3uEntry>[];
    final series = <M3uEntry>[];
    final tv     = <M3uEntry>[];
    try {
      await _parsePlaylistFile(
        m3uPath,
        films,
        series,
        tv,
        accountId: accountId,
        onProgress: onProgress,
        onDetail: onDetail,
      );
    } catch (e) {
      debugPrint('❌ ParsedPlaylist secondaire — parse échoué pour $accountName: $e');
      setLoadState(accountId, AccountLoadState.error,
          kind: LoadFailureKind.parse, detail: describeError(e));
      return;
    }
    final allEntries = [...films, ...series, ...tv];
    final modified = await File(m3uPath).lastModified();
    final playlist = ParsedPlaylist(
      accountId:    accountId,
      schema:       ParsedPlaylist.schemaVersion,
      m3uModifiedAt: modified,
      entries:      allEntries,
    );
    _memory[accountId] = playlist;
    _accountNames[accountId] = accountName;
    setLoadState(accountId, AccountLoadState.loaded);
    _bumpAfterLoad();
    _saveToDisk(accountId, playlist);
    debugPrint('✅ ParsedPlaylist secondaire: parse — $accountName (${allEntries.length} entrées)');
  }


  /// §catAudit — Journalise la couverture des CATÉGORIES d'un compte.
  ///
  /// Question à laquelle rien ne répondait : quand l'accueil n'affiche que
  /// « Autres », est-ce que le fournisseur ne donne aucun libellé de groupe, ou
  /// est-ce que `contentCategoryLabel` ne sait pas les traduire ? Les deux
  /// appellent des correctifs opposés, et on ne peut pas trancher depuis les
  /// dumps bruts (le champ `_cat` est ajouté au TÉLÉCHARGEMENT, il n'y figure
  /// pas).
  ///
  /// Une seule passe au chargement (quelques ms sur 150 000 entrées), et on
  /// n'imprime que les 8 groupes non traduits les plus fréquents — de quoi
  /// enrichir le mapping sans noyer le journal.
  static void _auditCategories(String accountName, List<M3uEntry> entries) {
    var sansGroupe = 0;
    var sansCategorie = 0;
    final orphelins = <String, int>{};
    for (final e in entries) {
      final g = e.groupTitle;
      if (g == null || g.isEmpty) {
        sansGroupe++;
        continue;
      }
      final c = e.category;
      if (c == null || c.isEmpty) {
        sansCategorie++;
        orphelins[g] = (orphelins[g] ?? 0) + 1;
      }
    }
    final total = entries.length;
    if (total == 0) return;
    final classes = total - sansGroupe - sansCategorie;
    final top = orphelins.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    debugPrint('🗂️ §catAudit $accountName : $classes/$total classés · '
        '$sansGroupe sans groupe · $sansCategorie groupes non traduits');
    for (final o in top.take(8)) {
      debugPrint('   ↳ non traduit ×${o.value} : "${o.key}"');
    }
  }

  /// §secondaryCounts — Totaux par type d'un compte, s'il est EN MÉMOIRE.
  static PlaylistCounts? countsInMemory(String accountId) {
    // ⚠️ Lecture directe de `_memory`, PAS `getAccount()` : celui-ci **touche
    // `_lastAccess`**, donc consulter un compteur repousserait le déchargement
    // du compte — l'inverse de ce qu'on veut.
    final p = _memory[accountId];
    if (p == null) return null;
    // Listes pré-splittées (`late final`) : aucun parcours des entrées.
    return PlaylistCounts(
      films: p.films.length,
      series: p.series.length,
      tv: p.tv.length,
    );
  }

  /// Mémo des en-têtes lus sur disque, par compte.
  ///
  /// ⚠️ Indispensable : la carte se reconstruit à chaque notification, et
  /// décompresser un en-tête à chaque rebuild annulerait tout le bénéfice.
  /// Invalidé par [invalidateCountsCache] quand le cache disque est réécrit.
  static final Map<String, PlaylistCounts> _diskCounts = {};

  static void invalidateCountsCache(String accountId) =>
      _diskCounts.remove(accountId);

  /// §secondaryCounts — Totaux d'un compte, mémoire d'abord, sinon **en-tête du
  /// cache disque**.
  ///
  /// Ne décompresse que la **première ligne** du NDJSON gzippé : on s'arrête
  /// dès qu'elle est lue, sans jamais matérialiser les 153 000 entrées.
  static Future<PlaylistCounts?> countsOf(String accountId) async {
    final mem = countsInMemory(accountId);
    if (mem != null) return mem;

    final cached = _diskCounts[accountId];
    if (cached != null) return cached;

    try {
      final path = await _diskCachePath(accountId);
      final file = File(path);
      if (!await file.exists()) return null;
      final line = await file
          .openRead()
          .transform(gzip.decoder)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first; // ⚠️ `.first` ferme le flux : rien d'autre n'est décompressé.
      final header = jsonDecode(line) as Map<String, dynamic>;
      final films = header['nFilms'] as int?;
      final series = header['nSeries'] as int?;
      final tv = header['nTv'] as int?;
      // Cache écrit AVANT §secondaryCounts : l'en-tête n'a pas les totaux. On
      // ne renvoie rien plutôt que des zéros — un « — » se lit mieux qu'un
      // faux « 0 », et le prochain rechargement les écrira.
      if (films == null || series == null || tv == null) return null;
      final counts = PlaylistCounts(films: films, series: series, tv: tv);
      _diskCounts[accountId] = counts;
      return counts;
    } catch (e) {
      debugPrint('⚠️ §secondaryCounts — en-tête illisible pour $accountId : $e');
      return null;
    }
  }

  // ── Accesseurs synchrones ─────────────────────────────────────────────────

  /// Toutes les entrées de tous les comptes actuellement chargés en mémoire.
  /// Utilisé par ActorDetailsPage, FavoritesService, etc.
  /// §tmdbMerge — Un catalogue vient d'entrer ou de sortir : la table de fusion
  /// par identifiant TMDB doit être refaite AVANT de notifier les vues, sinon
  /// elles regroupent une frame avec l'ancienne table.
  ///
  /// ⚠️ Appelé uniquement sur les chemins de CHARGEMENT / DÉCHARGEMENT, pas sur
  /// chaque notification : la reconstruction balaie toutes les entrées de tous
  /// les comptes (~350 000 sur les listes réelles).
  static void _bumpAfterLoad() {
    TmdbGroupAliasService.rebuild(entries);
    version.value++;
  }

  static List<M3uEntry> get entries {
    _touchAllLoaded();
    return _memory.values.expand((p) => p.entries).toList();
  }

  /// Entrées avec le compte prioritaire en PREMIER.
  /// À utiliser dans RechercheM3U pour que putIfAbsent donne la priorité
  /// aux URLs/qualités du compte actif sur les autres comptes chargés.
  static List<M3uEntry> entriesWithPriority(String priorityAccountId) {
    _touchAllLoaded();
    final priority = _memory[priorityAccountId]?.entries ?? [];
    final others   = _memory.entries
        .where((e) => e.key != priorityAccountId)
        .expand((e) => e.value.entries)
        .toList();
    return [...priority, ...others];
  }

  /// §perfBigList — Entrées DÉJÀ splittées par type, compte prioritaire d'abord.
  /// Réutilise les listes pré-splittées `films/series/tv` de chaque
  /// [ParsedPlaylist] (calculées une seule fois via `late final`) au lieu de
  /// re-parcourir TOUTES les entrées à chaque build de la home (crucial avec une
  /// playlist ~600k entrées). En mono-compte, renvoie directement les listes
  /// cachées (zéro copie). La TV n'est PAS filtrée des séparateurs déco ici : le
  /// filtre `isHiddenTvVariant` reste à la charge de l'appelant (couche feature).
  static Map<M3uContentType, List<M3uEntry>> byTypeWithPriority(
      String priorityAccountId) {
    _touchAllLoaded();
    final accounts = <ParsedPlaylist>[];
    final prio = _memory[priorityAccountId];
    if (prio != null) accounts.add(prio);
    for (final e in _memory.entries) {
      if (e.key != priorityAccountId) accounts.add(e.value);
    }
    if (accounts.length == 1) {
      final p = accounts.first;
      return {
        M3uContentType.movie: p.films,
        M3uContentType.series: p.series,
        M3uContentType.tv: p.tv,
      };
    }
    return {
      M3uContentType.movie: [for (final p in accounts) ...p.films],
      M3uContentType.series: [for (final p in accounts) ...p.series],
      M3uContentType.tv: [for (final p in accounts) ...p.tv],
    };
  }

  /// Playlist d'un compte spécifique (null si pas encore chargée).
  static ParsedPlaylist? getAccount(String accountId) {
    final p = _memory[accountId];
    if (p != null) _lastAccess[accountId] = DateTime.now();
    return p;
  }

  /// Nombre d'entrées en mémoire pour un compte (0 si non chargé).
  /// Lecture de stats : ne touche PAS `_lastAccess` (§lazyUnload).
  static int entriesCountOf(String accountId) =>
      _memory[accountId]?.entries.length ?? 0;

  /// §23 — Politique image « plus grosse liste » : pour un groupe
  /// multi-versions, l'image affichée vient de la version portée par le
  /// compte totalisant le PLUS d'entrées en mémoire (= la liste la plus
  /// riche, donc les visuels les plus soignés), avec fallback sur les
  /// suivantes par taille décroissante si elle n'a pas d'image. Décision
  /// utilisateur 2026-06-10 : « on prendra toujours celle de la plus grosse
  /// liste ». S'applique films + séries + chaînes.
  static String? bestLogoUrl(List<M3uEntry> versions) =>
      _bestImage(versions, (e) => e.logoUrl);

  /// §23 — Même politique pour les backdrops séries (champ v5).
  static String? bestBackdropUrl(List<M3uEntry> versions) =>
      _bestImage(versions, (e) => e.backdropUrl);

  /// §logoFallback — TOUTES les adresses d'image du groupe, dans l'ordre de
  /// préférence (compte le plus fourni d'abord), sans doublon ni valeur vide.
  ///
  /// [bestLogoUrl] n'en retournait qu'une, et rien ne réessayait les autres si
  /// elle ne chargeait pas. Or une adresse peut être **présente et morte** :
  /// le groupe perdait alors son affiche alors qu'une autre liste en proposait
  /// une valide.
  static List<String> logoCandidates(List<M3uEntry> versions) =>
      _imageCandidates(versions, (e) => e.logoUrl);

  static List<String> _imageCandidates(
    List<M3uEntry> versions,
    String? Function(M3uEntry) pick,
  ) {
    if (versions.isEmpty) return const [];
    final sorted = versions.length == 1
        ? versions
        : ([...versions]..sort((a, b) =>
            entriesCountOf(b.accountId).compareTo(entriesCountOf(a.accountId))));
    final out = <String>[];
    for (final v in sorted) {
      final img = pick(v);
      if (img == null || img.isEmpty) continue;
      if (!out.contains(img)) out.add(img);
    }
    return out;
  }

  static String? _bestImage(
    List<M3uEntry> versions,
    String? Function(M3uEntry) pick,
  ) {
    if (versions.isEmpty) return null;
    if (versions.length == 1) {
      final v = pick(versions.first);
      return (v == null || v.isEmpty) ? null : v;
    }
    final sorted = [...versions]..sort((a, b) =>
        entriesCountOf(b.accountId).compareTo(entriesCountOf(a.accountId)));
    for (final v in sorted) {
      final img = pick(v);
      if (img != null && img.isNotEmpty) return img;
    }
    return null;
  }

  /// Vrai si l'utilisateur a plusieurs listes → afficher les badges provider.
  ///
  /// §reloadScope — « Plusieurs listes » est une propriété de la CONFIGURATION,
  /// pas de l'état de la mémoire à l'instant du build (cf.
  /// [reportConfiguredAccounts]). Le repli sur [_memory] couvre le cas où
  /// personne n'a encore publié le compte.
  static bool get isMultiAccount =>
      _configuredAccounts > 1 || _memory.length > 1;

  /// Nom affiché d'un compte (pour les badges [Provider A] dans les action sheets).
  static String? accountName(String accountId) => _accountNames[accountId];

  // ── Invalidation ──────────────────────────────────────────────────────────

  /// Re-parse atomiquement la playlist depuis le disque sans laisser d'état vide.
  ///
  /// Contrairement à [invalidate] qui retire le compte de la mémoire AVANT le
  /// re-parse (provoquant un rebuild de la home sur état vide → bug ticket
  /// "Home vide après Recharger/Vider cache"), cette méthode :
  ///   1. Parse le nouveau M3U en arrière-plan (mémoire intacte pendant ce temps)
  ///   2. Swap atomiquement l'entrée mémoire (remove + add en une seule frame)
  ///   3. Bumpe `version` UNIQUEMENT à la fin → la home rebuild sur le nouvel état
  /// Le cache disque est régénéré à la suite (fire & forget).
  static Future<ParsedPlaylist?> reloadFromDisk(
    String accountId,
    String accountName,
    String m3uPath, {
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) async {
    if (!File(m3uPath).existsSync()) {
      debugPrint('⚠️ ParsedPlaylist.reloadFromDisk: fichier introuvable — $m3uPath');
      return null;
    }
    debugPrint('🔄 ParsedPlaylist: rechargement atomique — $accountName');

    final films  = <M3uEntry>[];
    final series = <M3uEntry>[];
    final tv     = <M3uEntry>[];
    try {
      await _parsePlaylistFile(
        m3uPath,
        films,
        series,
        tv,
        accountId: accountId,
        onProgress: onProgress,
        onDetail: onDetail,
      );
    } catch (e) {
      // §cacheKeep — Cet échec était MUET : `debugPrint` + `return null`, sans
      // aucun état d'erreur. `PlaylistReloadService` journalisait alors
      // « ✅ rechargée » sur une liste qui venait de disparaître de l'accueil.
      // On garde le `return null` (l'appelant en a besoin), mais on NOMME la
      // panne — pour l'écran comme pour le journal.
      debugPrint('❌ ParsedPlaylist.reloadFromDisk — parse échoué : $e');
      setLoadState(accountId, AccountLoadState.error,
          kind: LoadFailureKind.parse, detail: describeError(e));
      return null;
    }

    final allEntries = [...films, ...series, ...tv];
    final modified   = await File(m3uPath).lastModified();
    final playlist   = ParsedPlaylist(
      accountId:    accountId,
      schema:       ParsedPlaylist.schemaVersion,
      m3uModifiedAt: modified,
      entries:      allEntries,
    );

    // Swap atomique en mémoire : remove + add en une seule opération
    // synchrone.
    //
    // §cacheKeep — L'ancien cache disque n'est PLUS effacé ici. Il l'était
    // AVANT que `_saveToDisk` n'ait écrit son remplaçant : entre les deux, le
    // compte n'avait plus rien sur disque, et une interruption le laissait
    // durablement sans cache analysé. `_saveToDisk` écrit désormais dans un
    // `.part` puis renomme — il écrase l'ancien de façon atomique, sans jamais
    // ouvrir de fenêtre vide.
    _memory[accountId]       = playlist;
    _accountNames[accountId] = accountName;
    setLoadState(accountId, AccountLoadState.loaded);

    // Bump VERSION EN DERNIER → les listeners (home) rebuild sur le nouvel état.
    version.value++;

    _saveToDisk(accountId, playlist); // fire & forget
    debugPrint('✅ ParsedPlaylist.reloadFromDisk: ${allEntries.length} entrées');
    return playlist;
  }

  /// §cacheKeep — « La source vient de changer, la copie en mémoire est
  /// périmée » — **sans jamais toucher au fichier `.json.gz`**.
  ///
  /// **Le défaut corrigé** : les téléchargeurs appelaient `invalidate()` juste
  /// après avoir écrit un nouveau catalogue. Or `invalidate` **supprime le
  /// cache analysé**. Si l'analyse échouait ensuite — application tuée, OOM,
  /// fichier tronqué —, il ne restait plus rien : ni mémoire, ni disque. Et une
  /// liste absente de `_memory` est **totalement invisible** de l'accueil et de
  /// la recherche. C'est exactement ce qui a été constaté sur l'appareil :
  /// trois catalogues bruts sains sur disque, deux caches analysés seulement.
  ///
  /// Le principe : **un téléchargeur produit un fichier, il ne décide pas du
  /// cycle de vie du cache analysé.** La péremption est **déjà** détectée à la
  /// relecture, en comparant le `m3uModAt` de l'en-tête à la date de la source
  /// (cf. [_loadFromDisk]) : la suppression anticipée était redondante ET
  /// destructrice. Au pire on relit un cache périmé pendant quelques
  /// millisecondes avant qu'il ne soit refusé ; au mieux, il sert de filet
  /// quand l'analyse du nouveau catalogue échoue.
  /// §reloadScope — **La copie en mémoire n'est plus JETÉE ici.** Elle l'était,
  /// et c'est ce qui faisait disparaître la liste active de l'accueil, de la
  /// recherche et des fiches pendant tout le re-parse qui suit (des dizaines de
  /// secondes sur un gros catalogue) — alors que [reloadFromDisk] est écrit
  /// pour l'échanger d'un bloc, sans état vide. Sur un appareil à deux listes,
  /// ça se lisait comme « je n'ai plus qu'une liste » à chaque rechargement.
  ///
  /// On pose donc un drapeau : la copie reste AFFICHABLE, mais tout ce qui
  /// décide « faut-il (ré)analyser ? » la considère absente (cf. [_stale]).
  static void markStale(String accountId) {
    final bool inMemory = _memory.containsKey(accountId);
    if (!inMemory) {
      // Rien à afficher : l'état « pas chargée » reste la vérité, avec sa
      // raison.
      setLoadState(accountId, AccountLoadState.notLoaded,
          kind: LoadFailureKind.never,
          detail: 'source renouvelée, analyse à faire');
    }
    // ⚠️ APRÈS le `setLoadState` : déclarer une liste « chargée » lève le
    // drapeau (cf. [setLoadState]), le poser avant reviendrait à l'effacer.
    _stale.add(accountId);
    // ⚠️ Le message tient sur UNE ligne : le cliquet §l10nAll ne sait
    // reconnaître un diagnostic que sur la ligne qui porte `debugPrint(`.
    final String suite = inMemory ? ' (elle reste affichable)' : '';
    debugPrint('♻️ §reloadScope : $accountId — copie mémoire périmée$suite, cache disque CONSERVÉ');
  }

  /// Oublie **tout** d'un compte : mémoire ET cache disque.
  ///
  /// §cacheKeep — Réservé aux deux seuls cas où le cache analysé n'a plus
  /// aucune raison d'exister :
  ///   - le compte est supprimé, ou ses identifiants / son URL ont changé ;
  ///   - le schéma (ou le filtre de régions) a changé → le cache est illisible.
  ///
  /// ⚠️ **À ne PAS utiliser après un téléchargement** : c'est [markStale] qu'il
  /// faut. Un cache supprimé avant que son remplaçant n'existe est un cache
  /// perdu dès que l'analyse échoue.
  static void forget(String accountId) {
    _memory.remove(accountId);
    _stale.remove(accountId);
    invalidateCountsCache(accountId);
    setLoadState(accountId, AccountLoadState.notLoaded,
        kind: LoadFailureKind.cacheGone, detail: 'cache effacé volontairement');
    version.value++;
    _deleteDiskCache(accountId);
    debugPrint('🗑️ ParsedPlaylist: oublié (mémoire + disque) — $accountId');
  }

  /// Ancien nom de [forget], conservé pour les appelants hors de ce lot
  /// (`backup_service`, `web_console_service`, `accounts_page`,
  /// `region_filter_page`). Tous suppriment ou reconfigurent un compte : la
  /// sémantique « oublie tout » est bien celle qu'ils veulent.
  ///
  /// ⚠️ Pas d'annotation `@Deprecated` : l'analyseur en ferait sept
  /// *warnings* dans des fichiers appartenant à d'autres lots, et la consigne
  /// est de rendre `flutter analyze` vierge. Tout nouveau code appelle
  /// [forget] ou [markStale], jamais ce nom-ci.
  static void invalidate(String accountId) => forget(accountId);

  /// Vide entièrement la mémoire (ex: déconnexion globale).
  static void clear() {
    _memory.clear();
    _stale.clear();
    _accountNames.clear();
    _lastAccess.clear();
    _diskCounts.clear();
    loadStates.value = {};
    loadFailures.value = {};
    version.value++;
  }

  /// §lazyUnload — Décharge UN compte secondaire de la mémoire (le cache disque
  /// JSON.gz reste intact → rechargement ~50 ms quand re-demandé via
  /// [loadSecondary] ou [preloadOthersFromDisk]). Le compte actif ne doit
  /// JAMAIS être passé ici (vérif côté appelant). Bumpe `version` pour
  /// invalider les caches mémoire de la home (regroupements multi-comptes).
  /// L'état de chargement repasse à `notLoaded` → l'UI sait que la playlist
  /// est sur disque uniquement.
  static void unloadSecondary(String accountId) {
    if (!_memory.containsKey(accountId)) return;
    _memory.remove(accountId);
    _stale.remove(accountId);
    _lastAccess.remove(accountId);
    // §fleetState — `unloadedIdle` : la liste est SUR DISQUE, elle revient en
    // ~50 ms. Afficher « NON CHARGÉ » ici faisait passer un fonctionnement
    // parfaitement voulu pour une panne.
    setLoadState(accountId, AccountLoadState.notLoaded,
        kind: LoadFailureKind.unloadedIdle);
    version.value++;
    debugPrint('💤 ParsedPlaylist: déchargé mémoire (cache disque conservé) — $accountId');
  }

  /// §lazyUnload — Décharge tous les comptes secondaires inactifs depuis plus
  /// de [idle]. Le compte [activeAccountId] est protégé (jamais déchargé).
  /// À appeler périodiquement depuis l'UI (timer ~2 min) ou sur événement
  /// (passage au player, bascule d'écran). Retourne le nombre de comptes
  /// effectivement déchargés.
  static int unloadIdleSecondaries({
    required String activeAccountId,
    Duration idle = const Duration(minutes: 5),
  }) {
    final now = DateTime.now();
    final toUnload = <String>[];
    for (final id in _memory.keys) {
      if (id == activeAccountId) continue;
      final last = _lastAccess[id];
      // Si pas d'accès enregistré → marquer maintenant (grâce d'un cycle) puis
      // décharger au prochain passage.
      if (last == null) {
        _lastAccess[id] = now;
        continue;
      }
      if (now.difference(last) >= idle) toUnload.add(id);
    }
    for (final id in toUnload) {
      unloadSecondary(id);
    }
    return toUnload.length;
  }

  // ── Disque — JSON gzippé ──────────────────────────────────────────────────

  static Future<String> _diskCachePath(String accountId) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/parsed_playlist_$accountId.json.gz';
  }

  /// Lecture STREAMÉE du cache (NDJSON gzippé) : 1ʳᵉ ligne = en-tête
  /// (schema/accountId/m3uModAt), lignes suivantes = une entrée JSON chacune.
  /// On ne charge jamais toute la chaîne JSON en mémoire (anti-OOM grosse liste).
  ///
  /// §bootPercent — [onProgress]/[onDetail] rendent CE chemin observable.
  ///
  /// ⚠️ C'est le plus important des deux chemins : le parseur de catalogue ne
  /// tourne que lorsque le cache est absent ou périmé, alors que cette
  /// lecture-ci est celle de **chaque démarrage normal**. Elle ne publiait
  /// rien, puis `loadActive` annonçait 100 % — exactement le mensonge que
  /// §bootPercent corrige côté parseur, mais sur le chemin le plus fréquent.
  ///
  /// La progression est dérivée des **octets compressés lus**, et non d'un
  /// compte de lignes : le nombre total de lignes n'est connu qu'à la fin,
  /// alors que la taille du fichier est connue avant de l'ouvrir. Le gunzip
  /// consomme par blocs, donc la valeur avance par paliers — mais elle est
  /// monotone et bornée à 1.
  static Future<ParsedPlaylist?> _loadFromDisk(
    String accountId,
    String m3uPath, {
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) async {
    final path = await _diskCachePath(accountId);
    final cacheFile = File(path);
    if (!await cacheFile.exists()) {
      // §cacheKeep — Sortie jusqu'ici MUETTE. C'était la plus fréquente des
      // trois façons de perdre une liste, et la seule qui ne laissait pas la
      // moindre trace : l'appelant enchaînait sur un parse complet (ou sur
      // rien du tout, au préchargement) sans qu'on sache pourquoi.
      debugPrint('ℹ️ §cacheKeep : aucun cache analysé sur disque — $accountId');
      return null;
    }

    try {
      final int totalBytes = await cacheFile.length();
      int readBytes = 0;
      int lastBucket = -1;

      final lines = cacheFile
          .openRead()
          .map((chunk) {
            readBytes += chunk.length;
            return chunk;
          })
          .transform(gzip.decoder)
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      Map<String, dynamic>? header;
      DateTime? m3uModifiedAt;
      // §cacheKeep — Nombre d'entrées ANNONCÉ par l'en-tête. C'est le seul
      // moyen de reconnaître un cache tronqué : le gunzip d'un fichier coupé
      // lève souvent, mais pas toujours (une coupure pile sur une frontière de
      // bloc se lit comme une fin de fichier propre).
      int? declaredCount;
      final entries = <M3uEntry>[];
      // §ramDiet — Pool d'internement, le temps du chargement (cf. `StringPool`).
      //
      // C'est le chemin de CHAQUE démarrage, et le plus coûteux en mémoire
      // RÉSIDENTE : `jsonDecode` fabrique une chaîne neuve par champ et par
      // ligne, donc autant de copies de « Films | Action », de « FHD » ou de
      // l'identifiant de compte qu'il y a d'entrées — des centaines de milliers.
      // Le pool meurt avec cette méthode ; les chaînes canoniques restent,
      // partagées par les entrées.
      final pool = StringPool();

      await for (final line in lines) {
        if (line.isEmpty) continue;
        if (header == null) {
          header = jsonDecode(line) as Map<String, dynamic>;
          final schema = header['schema'] as int;
          // Invalider si schéma obsolète
          if (schema != ParsedPlaylist.schemaVersion) {
            debugPrint('⚠️ ParsedPlaylist: schéma v$schema obsolète (v${ParsedPlaylist.schemaVersion} attendu) → invalidation');
            await cacheFile.delete();
            return null;
          }
          declaredCount = header['count'] as int?;
          m3uModifiedAt = DateTime.parse(header['m3uModAt'] as String);
          // §langFilter — Invalider si le filtre de régions a changé depuis le
          // cache (le cache ne contient que les entrées non masquées d'alors).
          final cachedSig = (header['filterSig'] as String?) ?? '';
          if (cachedSig != HiddenRegionsService.signature) {
            debugPrint('⚠️ ParsedPlaylist: filtre régions modifié → re-parse');
            await cacheFile.delete();
            return null;
          }
          // Invalider si le fichier .m3u a été re-téléchargé depuis
          final m3uFile = File(m3uPath);
          if (!await m3uFile.exists()) return null;
          final m3uModified = await m3uFile.lastModified();
          if (m3uModifiedAt.isBefore(m3uModified.subtract(const Duration(seconds: 5)))) {
            debugPrint('⚠️ ParsedPlaylist: fichier M3U modifié → re-parse nécessaire');
            await cacheFile.delete();
            return null;
          }
        } else {
          entries.add(
              M3uEntry.fromJson(jsonDecode(line) as Map<String, dynamic>, pool));
          // Throttle au pourcentage entier : sans lui, 600 000 entrées
          // reconstruiraient 600 000 fois la même ligne de texte.
          if (onProgress != null || onDetail != null) {
            final double v = totalBytes > 0
                ? (readBytes / totalBytes).clamp(0.0, 1.0)
                : 0.0;
            final int bucket = (v * 100).round();
            if (bucket != lastBucket) {
              lastBucket = bucket;
              onProgress?.call(v);
              onDetail?.call('${formatCount(entries.length)} entrées');
            }
          }
        }
      }

      if (header == null || m3uModifiedAt == null) {
        debugPrint('❌ §cacheKeep : cache sans en-tête exploitable — $accountId '
            '→ supprimé');
        try { await cacheFile.delete(); } catch (_) {}
        return null;
      }

      // §cacheKeep — Cache TRONQUÉ : l'en-tête annonce des entrées, le corps
      // n'en livre aucune. C'était le SEUL scénario où la lecture « réussissait »
      // en rendant une playlist vide — que `loadActive` acceptait ensuite comme
      // `loaded`. Le compte devenait invisible de l'accueil et de la recherche
      // sans qu'une seule erreur ne soit journalisée.
      if (declaredCount != null && declaredCount > 0 && entries.isEmpty) {
        debugPrint('❌ §cacheKeep : cache TRONQUÉ — l\'en-tête annonce '
            '$declaredCount entrées, 0 lue → supprimé ($accountId)');
        try { await cacheFile.delete(); } catch (_) {}
        return null;
      }

      // Une liste à zéro entrée n'est JAMAIS un succès : la rendre ici la
      // ferait accepter comme `loaded`, et le compte afficherait « DISPONIBLE »
      // avec un accueil vide. On la refuse — le fichier est conservé, c'est à
      // une ré-analyse de la source de trancher.
      if (entries.isEmpty) {
        debugPrint('⚠️ §cacheKeep : cache VIDE (0 entrée) — refusé pour '
            '$accountId, une liste sans entrée n\'est pas un chargement réussi');
        return null;
      }

      return ParsedPlaylist(
        accountId:     header['accountId'] as String,
        schema:        header['schema'] as int,
        m3uModifiedAt: m3uModifiedAt,
        entries:       entries,
      );
    } catch (e) {
      debugPrint('❌ ParsedPlaylist: erreur chargement disque — $e');
      // Cache potentiellement corrompu → on le supprime pour repartir propre.
      try { if (await cacheFile.exists()) await cacheFile.delete(); } catch (_) {}
      return null;
    }
  }

  /// Écriture STREAMÉE du cache (NDJSON gzippé). On encode une entrée à la fois
  /// et on pousse les octets gzippés dans l'IOSink → empreinte mémoire minime
  /// même pour ~600k entrées (l'ancienne version `jsonEncode(toJson())` faisait
  /// une chaîne géante de 150-300 Mo d'un coup → OOM silencieux sur Fire Stick →
  /// aucun cache écrit → re-parse à chaque démarrage).
  ///
  /// §cacheKeep — **L'écriture est ATOMIQUE.** Elle allait directement sur la
  /// destination : une interruption (application tuée, disque plein, OOM) y
  /// laissait un `.gz` tronqué, c'est-à-dire un cache qui existe, qu'on relit,
  /// et qui rend une liste vide. Les deux autres écrivains de l'app
  /// (`XtreamCatalogService`, `ensureDownloadedForAccount`) écrivaient déjà en
  /// `.part` + `rename` ; celui-ci était le seul à ne pas le faire — et c'est
  /// justement lui qui écrit le fichier le plus long à produire.
  static Future<void> _saveToDisk(String accountId, ParsedPlaylist playlist) async {
    final path = await _diskCachePath(accountId);
    final partPath = '$path.part';
    final part = File(partPath);
    final raw = part.openWrite();
    var closed = false;
    try {
      final gzipSink = gzip.encoder.startChunkedConversion(_IOSinkAdapter(raw));
      void writeLine(Object o) => gzipSink.add(utf8.encode('${jsonEncode(o)}\n'));

      // En-tête
      writeLine({
        'schema':    playlist.schema,
        'accountId': playlist.accountId,
        'm3uModAt':  playlist.m3uModifiedAt.toIso8601String(),
        'count':     playlist.entries.length,
        // §secondaryCounts — Totaux par type, écrits dans l'EN-TÊTE.
        //
        // Ils étaient recomptés en RAM à chaque affichage, en parcourant
        // jusqu'à 153 000 entrées — et surtout, ils tombaient à **zéro** dès
        // qu'un compte secondaire était déchargé, laissant croire à une liste
        // vide. Dans l'en-tête, ils sont **exacts et instantanés**, y compris
        // compte déchargé, et se lisent sans décompresser tout le fichier.
        'nFilms':    playlist.films.length,
        'nSeries':   playlist.series.length,
        'nTv':       playlist.tv.length,
        // §langFilter — signature du filtre de régions au moment du parse.
        'filterSig': HiddenRegionsService.signature,
      });
      // Une entrée par ligne
      for (final e in playlist.entries) {
        writeLine(e.toJson());
      }
      // ⚠️ ORDRE CRITIQUE, et c'est tout l'intérêt de `_IOSinkAdapter` :
      //   1. `gzipSink.close()` pousse le TRAILER gzip dans l'IOSink — sans
      //      lui, le fichier est un `.gz` invalide (l'adaptateur a un `close()`
      //      volontairement no-op pour que l'IOSink survive à cette étape) ;
      //   2. `flush` + `close` de l'IOSink : les octets sont sur le disque ;
      //   3. SEULEMENT ENSUITE le `rename`.
      // Renommer avant le trailer publierait exactement le fichier tronqué
      // qu'on cherche à ne plus jamais écrire.
      gzipSink.close();
      await raw.flush();
      await raw.close();
      closed = true;

      // Publication atomique. Tant que ce `rename` n'a pas eu lieu, l'ANCIEN
      // cache reste intact et lisible ; une interruption ne laisse qu'un
      // `.part` orphelin, jamais un cache à moitié écrit.
      await part.rename(path);

      // §secondaryCounts — L'en-tête vient de changer : le mémo est périmé.
      _diskCounts.remove(playlist.accountId);
      debugPrint('💾 ParsedPlaylist: sauvegardé (streamé, atomique) — ${playlist.entries.length} entrées');
    } catch (e) {
      // §cacheKeep — On ne touche PAS à la destination : l'ancien cache, même
      // périmé, vaut infiniment mieux que pas de cache du tout.
      debugPrint('❌ ParsedPlaylist: erreur sauvegarde disque — $e '
          '(ancien cache conservé)');
      if (!closed) {
        try { await raw.close(); } catch (_) {}
      }
      try { if (await part.exists()) await part.delete(); } catch (_) {}
    }
  }

  // ── Ouvertures minimales pour les tests (§cacheKeep) ──────────────────────
  //
  // Le cycle « écrire → relire » est le cœur du correctif : c'est là que se
  // jouent l'atomicité, la détection de cache tronqué et le refus d'une liste
  // vide. Trois passe-plats suffisent à le tester sans rien rendre public.

  @visibleForTesting
  static Future<String> diskCachePathForTest(String accountId) =>
      _diskCachePath(accountId);

  @visibleForTesting
  static Future<void> saveToDiskForTest(
          String accountId, ParsedPlaylist playlist) =>
      _saveToDisk(accountId, playlist);

  @visibleForTesting
  static Future<ParsedPlaylist?> loadFromDiskForTest(
          String accountId, String sourcePath) =>
      _loadFromDisk(accountId, sourcePath);

  static Future<void> _deleteDiskCache(String accountId) async {
    try {
      final path = await _diskCachePath(accountId);
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Adaptateur : expose un [IOSink] (fichier) comme un `Sink<List<int>>` pour le
/// brancher en sortie de `gzip.encoder.startChunkedConversion`. Le `close()` est
/// volontairement no-op : l'`IOSink` est fermé explicitement par l'appelant
/// (`_saveToDisk`) après le flush du trailer gzip.
class _IOSinkAdapter implements Sink<List<int>> {
  final IOSink _out;
  _IOSinkAdapter(this._out);

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void close() {}
}
