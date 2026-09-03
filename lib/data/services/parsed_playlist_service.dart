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
///   4. [invalidate] — appelé par PlaylistService après téléchargement d'une nouvelle playlist
class ParsedPlaylistService {
  // ── Mémoire — persiste toute la session app ───────────────────────────────
  static final Map<String, ParsedPlaylist> _memory = {};
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

  /// Marque l'état d'un compte et notifie les listeners (immutable copy).
  static void setLoadState(String accountId, AccountLoadState state) {
    final next = Map<String, AccountLoadState>.from(loadStates.value);
    if (state == AccountLoadState.notLoaded) {
      next.remove(accountId);
    } else {
      next[accountId] = state;
    }
    loadStates.value = next;
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
    // 1. Déjà en mémoire
    if (_memory.containsKey(accountId)) {
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
      setLoadState(accountId, AccountLoadState.error);
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
      if (_memory.containsKey(acc.id)) continue;
      // §23 — Résolution du fichier source (même convention que
      // PlaylistService.pathForAccountId, dupliquée ici pour éviter un import
      // circulaire) : catalogue .json prioritaire, sinon .m3u legacy.
      final dir = await getApplicationDocumentsDirectory();
      var m3uPath = '${dir.path}/playlist_${acc.id}.json';
      if (!File(m3uPath).existsSync()) {
        m3uPath = '${dir.path}/playlist_${acc.id}.m3u';
      }
      if (!File(m3uPath).existsSync()) continue;

      final disk = await _loadFromDisk(acc.id, m3uPath);
      if (disk != null) {
        _memory[acc.id] = disk;
        _accountNames[acc.id] = acc.label;
        setLoadState(acc.id, AccountLoadState.loaded);
        debugPrint('✅ ParsedPlaylist: préchargé depuis disque — ${acc.label} (${disk.entries.length} entrées)');
        _auditCategories(acc.label, disk.entries);
        _bumpAfterLoad();
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
    if (_memory.containsKey(accountId)) {
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
      setLoadState(accountId, AccountLoadState.error);
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

  /// Vrai si plusieurs comptes sont chargés en mémoire → afficher les badges provider.
  static bool get isMultiAccount => _memory.length > 1;

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
      debugPrint('❌ ParsedPlaylist.reloadFromDisk — parse échoué : $e');
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

    // Swap atomique — l'ancien cache disque est effacé, le nouveau remplace
    // l'ancien en mémoire en une seule opération synchrone.
    await _deleteDiskCache(accountId);
    _memory[accountId]       = playlist;
    _accountNames[accountId] = accountName;
    setLoadState(accountId, AccountLoadState.loaded);

    // Bump VERSION EN DERNIER → les listeners (home) rebuild sur le nouvel état.
    version.value++;

    _saveToDisk(accountId, playlist); // fire & forget
    debugPrint('✅ ParsedPlaylist.reloadFromDisk: ${allEntries.length} entrées');
    return playlist;
  }

  /// Invalide le cache mémoire + disque pour un compte (lazy : ne re-parse pas).
  ///
  /// ⚠️ Provoque un état temporairement vide en mémoire pour ce compte. À ne PAS
  /// utiliser pour le compte actif si un rebuild de la home est imminent — préférer
  /// [reloadFromDisk] qui swap atomiquement. Reste utile pour :
  ///   - Suppression d'un compte (le compte n'existe plus)
  ///   - Invalidation d'un compte secondaire (lazy reload au prochain accès)
  static void invalidate(String accountId) {
    _memory.remove(accountId);
    setLoadState(accountId, AccountLoadState.notLoaded);
    version.value++;
    _deleteDiskCache(accountId);
    debugPrint('🗑️ ParsedPlaylist: cache invalidé — $accountId');
  }

  /// Vide entièrement la mémoire (ex: déconnexion globale).
  static void clear() {
    _memory.clear();
    _accountNames.clear();
    _lastAccess.clear();
    loadStates.value = {};
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
    _lastAccess.remove(accountId);
    setLoadState(accountId, AccountLoadState.notLoaded);
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
    if (!await cacheFile.exists()) return null;

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

      if (header == null || m3uModifiedAt == null) return null;
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
  static Future<void> _saveToDisk(String accountId, ParsedPlaylist playlist) async {
    final path = await _diskCachePath(accountId);
    final raw = File(path).openWrite();
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
      gzipSink.close(); // flush du trailer gzip dans l'IOSink
      await raw.flush();
      // §secondaryCounts — L'en-tête vient de changer : le mémo est périmé.
      _diskCounts.remove(playlist.accountId);
      debugPrint('💾 ParsedPlaylist: sauvegardé (streamé) — ${playlist.entries.length} entrées');
    } catch (e) {
      debugPrint('❌ ParsedPlaylist: erreur sauvegarde disque — $e');
    } finally {
      await raw.close();
    }
  }

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
