import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import '../../core/utils/network.dart';
import '../../core/utils/host_gate.dart';
import '../../core/utils/keyed_serial.dart';
import '../../core/utils/user_error.dart';
import '../../l10n/l10n_ext.dart';
import 'load_failure.dart';
import 'playlist_fallback_policy.dart';
import 'stream_account_service.dart';
import 'parsed_playlist_service.dart';
import 'xtream_catalog_service.dart';

/// §23 — Pipeline playlist à deux niveaux :
///   - **TENTATIVE 1 (JSON direct)** : `XtreamCatalogService.downloadCatalog`
///     sauvegarde les réponses brutes `player_api.php` dans
///     `playlist_<id>.json` → parsé par `XtreamCatalogParser` (zéro perte :
///     tmdb_id, synopsis, backdrops, tv_archive…).
///   - **TENTATIVE 2 (fallback)** : `get.php` historique → `playlist_<id>.m3u`
///     → parsé par `M3uParser` (regex). Pour les comptes non-Xtream
///     (Flussonic, M3U custom) ou les panels sans JSON API.
/// Un compte n'a qu'UN des deux fichiers à la fois (l'autre est supprimé au
/// téléchargement) ; [pathForAccountId] résout celui qui existe.
class PlaylistService {
  static const String _playlistBaseName = 'playlist';
  static const Duration playlistCacheDuration = Duration(hours: 24);

  /// §cacheKeep — Taille PLANCHER d'un catalogue crédible, en octets.
  ///
  /// Le seul test était `> 0 octet`. Or ce que renvoie un panel en panne n'est
  /// pas un fichier vide : c'est une page d'erreur HTML, un « Access denied »
  /// ou un JSON `{"user_info":{"auth":0}}` — deux ou trois kilo-octets qui
  /// passent le test, sont renommés en `.json`/`.m3u`, et **font autorité
  /// pendant 24 h** parce que le TTL les considère comme un cache sain. La
  /// liste de l'utilisateur disparaît alors pour une journée entière, sans
  /// qu'aucune erreur ne soit levée nulle part.
  ///
  /// **Pourquoi 4 Ko et pas 1 Ko** : un plancher à 1 Ko ne réglerait PAS le cas
  /// qui a motivé ce garde-fou — une page d'erreur de 2 Ko le franchit sans
  /// difficulté. Il faut se placer au-dessus de ce qu'un panel en panne peut
  /// produire (quelques kilo-octets de HTML ou de JSON d'erreur) et très en
  /// dessous du plus petit catalogue réel observé, qui dépasse le mégaoctet :
  /// entre les deux, il y a trois ordres de grandeur, donc aucune finesse à
  /// avoir.
  ///
  /// Le prix d'un faux positif est faible et réversible — une liste écrite à la
  /// main de moins d'une quarantaine de lignes serait retéléchargée à chaque
  /// contrôle. Le prix d'un faux négatif, lui, est la disparition de la liste
  /// pendant 24 h. Le curseur penche donc du côté prudent.
  static const int minPlaylistBytes = 4096;

  static Future<String> playlistPath() async {
    final acc = await StreamAccountService.getCurrentAccount();
    if (acc == null) {
      throw const HttpException(
          "Aucun compte actif sélectionné. Veuillez en choisir un dans les paramètres.");
    }
    return pathForAccountId(acc.id);
  }

  /// §23 — Chemin du catalogue JSON (pipeline player_api direct).
  static Future<String> jsonPathForAccountId(String accountId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${_playlistBaseName}_$accountId.json';
  }

  /// Chemin du fichier M3U legacy (fallback get.php).
  static Future<String> m3uPathForAccountId(String accountId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${_playlistBaseName}_$accountId.m3u';
  }

  /// §23 — Résout le fichier playlist EXISTANT d'un compte : `.json`
  /// (pipeline JSON) prioritaire, sinon `.m3u` (fallback/legacy). Si aucun
  /// n'existe, retourne le chemin `.json` (destination par défaut du prochain
  /// téléchargement — `File(path).exists()` rendra `false` côté appelant).
  static Future<String> pathForAccountId(String accountId) async {
    final jsonPath = await jsonPathForAccountId(accountId);
    if (File(jsonPath).existsSync()) return jsonPath;
    final m3uPath = await m3uPathForAccountId(accountId);
    if (File(m3uPath).existsSync()) return m3uPath;
    return jsonPath;
  }

  /// Supprime les fichiers playlist (json + m3u) en cache pour un compte.
  static Future<void> deleteForAccountId(String accountId) async {
    for (final path in [
      await jsonPathForAccountId(accountId),
      await m3uPathForAccountId(accountId),
    ]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// §bootStatus — [onDownloadStart] est appelé UNIQUEMENT si un téléchargement
  /// réseau va réellement démarrer (cache absent ou périmé). L'appelant peut
  /// ainsi afficher « téléchargement… » au lieu de « lecture du cache… » sans
  /// que ce service connaisse l'UI.
  /// §bootActiveCap (2026-09-09) — Le téléchargement en vol, partagé.
  ///
  /// ⚠️ **Sans lui, « Réessayer » lançait un SECOND téléchargement** du même
  /// fichier, au même endroit, pendant que le premier écrivait encore son
  /// `.part` — deux handles sur le même fichier partiel. Le défaut existait
  /// déjà avant l'écran de démarrage interruptible : il suffisait d'appuyer
  /// sur « Réessayer » depuis l'écran d'erreur pendant qu'un téléchargement
  /// lent tournait encore. Un second appel attend désormais le premier.
  static Future<String>? _inFlight;

  static Future<String> getOrDownloadPlaylist({
    void Function()? onDownloadStart,
  }) {
    final Future<String>? running = _inFlight;
    if (running != null) {
      debugPrint('⏳ Telechargement de la playlist deja en cours : on attend le meme.');
      return running;
    }
    final Future<String> started = _getOrDownloadPlaylist(
      onDownloadStart: onDownloadStart,
    );
    _inFlight = started;
    return started.whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    });
  }

  static Future<String> _getOrDownloadPlaylist({
    void Function()? onDownloadStart,
  }) async {
    // revue 2026-09-11, D1A-02 — Le contrôle de fraîcheur ET le téléchargement
    // se font sous le verrou du compte : un rafraîchissement lancé en même
    // temps (`refreshIfStale` au changement de principal) doit trouver ici un
    // fichier NEUF, pas en retélécharger un second derrière celui-ci.
    final String key = await _currentAccountKey();
    return _downloads.run(key, () async {
      final path = await playlistPath();
      final file = File(path);
      final bool exists = await file.exists();
      final int length = exists ? await file.length() : 0;
      final Duration? age = exists
          ? DateTime.now().difference(await file.lastModified())
          : null;

      // revue 2026-09-11, D1A-19 — Le compte PRINCIPAL ignorait le plancher
      // §cacheKeep : il ne regardait que l'existence et l'âge. Une page
      // d'erreur de 2 Ko renommée en source faisait donc autorité 24 h —
      // accueil vide et puce « DISPONIBLE ». Même règle que les secondaires.
      if (!needsDownload(exists: exists, lengthBytes: length, age: age)) {
        debugPrint(
            "✅ Playlist trouvée en cache et encore valide. Pas de téléchargement.");
        return path;
      }
      if (!exists) {
        debugPrint("ℹ️ Aucune playlist en cache. Téléchargement initial...");
      } else if (length < minPlaylistBytes) {
        debugPrint('⏳ Playlist en cache suspecte ($length octets < $minPlaylistBytes) → retéléchargement.');
      } else {
        debugPrint(
            "⏳ Playlist trouvée en cache mais périmée. Retéléchargement...");
      }
      onDownloadStart?.call();
      try {
        return (await _downloadCurrentM3UImpl()).path;
      } catch (e) {
        // revue 2026-09-11, D1A-19 (relecture) — Le plancher ne doit pas coûter
        // une liste qui MARCHAIT. Une petite liste M3U écrite à la main (moins
        // de 4 Ko, quelques chaînes) encore dans son TTL était servie telle
        // quelle ; le plancher la fait désormais retélécharger, et sans réseau
        // ce téléchargement lève — le démarrage s'arrêtait alors sur une
        // erreur là où il ouvrait l'accueil. On la garde, comme avant, mais
        // seulement si elle RESSEMBLE à une liste : une page d'erreur en cache
        // (le cas que vise le plancher) laisse l'erreur réelle remonter.
        if (exists &&
            length < minPlaylistBytes &&
            age != null &&
            age < playlistCacheDuration &&
            !path.toLowerCase().endsWith('.json') &&
            await _isCredibleM3uFile(file)) {
          debugPrint('⚠️ D1A-19 : retéléchargement impossible ($e) — la petite liste en cache, encore fraîche, reste servie.');
          return path;
        }
        rethrow;
      }
    });
  }

  /// revue 2026-09-11, D1A-02 — Les téléchargements de LISTE, un à la fois par
  /// compte.
  ///
  /// ⚠️ **Le défaut.** Seul `getOrDownloadPlaylist` avait un verrou
  /// (`_inFlight`). Passer en principal un compte déchargé et périmé
  /// déclenchait DEUX téléchargements complets du même catalogue : celui de
  /// `HomePage._ensureLoaded` (via `getOrDownloadPlaylist`) et celui de
  /// `refreshIfStale` (via `ensureDownloadedForAccount`) — deux fois la charge
  /// sur un panel limité à une connexion (§hostGate), et deux écritures dans
  /// les MÊMES `.part` (`playlist_<id>.json.part`, `playlist_<id>.m3u.part`).
  ///
  /// Le second appelant attend la fin du premier, puis fait SON travail : un
  /// contrôle de fraîcheur trouve alors le fichier neuf et ne télécharge rien ;
  /// un rechargement forcé, lui, retélécharge vraiment.
  ///
  /// ⚠️ Les `.part` gardent un nom FIXE, volontairement : sous ce verrou, deux
  /// écritures du même compte ne peuvent plus se chevaucher dans le processus,
  /// et un nom fixe est réécrit (donc nettoyé) au téléchargement suivant — un
  /// nom unique par écriture laisserait, lui, un orphelin de plusieurs dizaines
  /// de Mo à chaque interruption, que le balayage §acctPurge ne reconnaît pas.
  static final KeyedSerial _downloads = KeyedSerial();

  /// Clé du verrou pour le compte courant (`''` si aucun, ou si la lecture du
  /// stockage échoue — l'erreur réelle sera levée, comme avant, par le corps).
  static Future<String> _currentAccountKey() async {
    try {
      return (await StreamAccountService.getCurrentAccount())?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  /// revue 2026-09-11, D1A-02 + D3B-02 (relecture) — Un téléchargement de la
  /// liste de ce compte est-il en cours (ou en file) ? Lu par le réconciliateur
  /// §fleetLoad, qui décide de FORCER un téléchargement sur des faits relevés
  /// AVANT d'attendre ce verrou (cf. `PlaylistFleetService._run`).
  static bool isDownloadInProgress(String accountId) =>
      _downloads.isBusy(accountId);

  static void _logWaitIfBusy(String key, String label) {
    if (_downloads.isBusy(key)) {
      debugPrint('⏳ D1A-02 : un téléchargement de « $label » est déjà en cours → on attend la fin avant le nôtre.');
    }
  }

  // ── Points d'injection pour les tests (revue 2026-09-11, D1A-01/D1A-02) ──
  //
  // Le cycle « catalogue refusé → repli ou non → validation → publication »
  // est le cœur du correctif, et il se joue sur le disque : ces deux crochets
  // remplacent le réseau SANS rien court-circuiter d'autre (verrou, plancher,
  // validation, renommage, suppression de l'autre format).

  /// Remplace `XtreamCatalogService.downloadCatalog` (test uniquement).
  @visibleForTesting
  static Future<CatalogDownloadResult> Function(
      StreamAccount acc, String jsonPath)? catalogDownloaderForTest;

  /// Remplace le téléchargement `get.php` vers [tempPath] (test uniquement).
  @visibleForTesting
  static Future<void> Function(String url, String tempPath)?
      getPhpDownloaderForTest;

  static Future<CatalogDownloadResult> _downloadCatalog(
      StreamAccount acc, String jsonPath) {
    final hook = catalogDownloaderForTest;
    if (hook != null) return hook(acc, jsonPath);
    return XtreamCatalogService.downloadCatalog(acc, jsonPath);
  }

  /// Le téléchargement `get.php` des deux chemins (ils étaient identiques).
  static Future<void> _fetchGetPhp(
      StreamAccount? acc, String url, String tempPath) async {
    final hook = getPhpDownloaderForTest;
    if (hook != null) return hook(url, tempPath);
    // §cookieScope — Le compte est PASSÉ au constructeur : sans lui, la
    // requête d'un compte secondaire partait avec les cookies du principal.
    // `acc` peut être nul (chemin legacy sans compte résolu).
    final dio = await NetworkUtils.buildDio(url, account: acc);
    // §hostGate — Le repli `get.php` passe par le MÊME portillon que les
    // requêtes `player_api.php` : sans lui, deux comptes du même fournisseur
    // pouvaient encore se marcher dessus par ce chemin, sur des panels
    // limités à une connexion simultanée.
    await HostGate.run(url, () async {
      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
    });
  }

  /// revue 2026-09-11, D1A-01 — Un `.json` qui mérite d'être PROTÉGÉ : présent
  /// et au-dessus du plancher §cacheKeep. Un fichier plus petit est une page
  /// d'erreur en cache, pas un catalogue : il ne bloque pas le repli.
  static bool _hasCredibleJson(String jsonPath) {
    try {
      final f = File(jsonPath);
      return f.existsSync() && f.lengthSync() >= minPlaylistBytes;
    } catch (_) {
      return false;
    }
  }

  /// revue 2026-09-11, D1A-01 — Ce que `get.php` vient d'écrire est-il une
  /// liste ? (cf. [isCredibleM3u]). Ne lève jamais.
  static Future<bool> _isCredibleM3uFile(File f) async {
    try {
      if (!await f.exists()) return false;
      final int length = await f.length();
      final RandomAccessFile raf = await f.open();
      try {
        final List<int> head = await raf.read(m3uHeadBytes);
        return isCredibleM3u(lengthBytes: length, head: head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// §secondaryRefresh — Décision « faut-il (re)télécharger ? », isolée en
  /// fonction PURE pour être testable sans système de fichiers.
  ///
  /// [age] est l'âge du cache (`null` si le fichier n'existe pas).
  /// [respectTtl] à `false` = on ne télécharge que si le fichier manque
  /// (ancien comportement de [ensureDownloadedForAccount], conservé pour les
  /// appelants qui veulent seulement *peupler* un compte).
  ///
  /// §cacheKeep — [minBytes] est le plancher de crédibilité (cf.
  /// [minPlaylistBytes]) : un fichier plus petit est traité comme absent, quel
  /// que soit son âge et **même en mode « peupler seulement »**. Une page
  /// d'erreur de 2 Ko renommée en `.m3u` n'est pas un cache, c'est un cache
  /// empoisonné.
  @visibleForTesting
  static bool needsDownload({
    required bool exists,
    required int lengthBytes,
    required Duration? age,
    bool respectTtl = true,
    int minBytes = minPlaylistBytes,
  }) {
    if (!exists || lengthBytes < minBytes) return true;
    if (!respectTtl || age == null) return false;
    return age >= playlistCacheDuration;
  }

  /// §bootHydrate — « Ce compte a-t-il VRAIMENT du travail ? », sans rien
  /// déclencher.
  ///
  /// C'est la question qui permet de ne rallonger le démarrage que les jours où
  /// c'est nécessaire : cache frais → le boot ne bouge pas d'une milliseconde ;
  /// cache absent ou périmé → on paie devant l'écran d'étapes plutôt que
  /// derrière l'accueil.
  ///
  /// ⚠️ Ne répond QUE sur le téléchargement. Un compte dont le fichier est
  /// frais mais qui n'est pas en mémoire a quand même du travail (le parsing) —
  /// c'est à l'appelant de croiser avec `ParsedPlaylistService.stateOf`. Sans
  /// ce croisement, un compte dont le préchargement disque a échoué ne serait
  /// plus jamais chargé.
  ///
  /// ⚠️ En cas d'erreur d'accès disque, répond **oui**. Un `stat` qui échoue ne
  /// doit pas décider à la place du démarrage : l'hydratation, elle, sait
  /// échouer proprement.
  static Future<bool> hasPendingWork(StreamAccount acc) async {
    try {
      final file = File(await pathForAccountId(acc.id));
      final bool exists = await file.exists();
      return needsDownload(
        exists: exists,
        lengthBytes: exists ? await file.length() : 0,
        age: exists
            ? DateTime.now().difference(await file.lastModified())
            : null,
      );
    } catch (e) {
      debugPrint('⚠️ hasPendingWork(${acc.label}) : $e → on suppose du travail');
      return true;
    }
  }

  /// Télécharge la playlist d'un compte spécifique (comptes non-actifs en
  /// multi-comptes). Ne lève jamais : renvoie `path: null` en cas d'échec.
  ///
  /// §secondaryRefresh — **Le TTL s'applique désormais ici aussi.** Avant, la
  /// seule condition était l'existence physique du fichier : une playlist
  /// secondaire téléchargée une fois restait figée indéfiniment (le TTL de 24 h
  /// n'était lu que dans [getOrDownloadPlaylist], qui ne concerne que le compte
  /// actif). Coût quand le cache est frais : un `stat`, rien de plus.
  ///
  /// `downloaded` dit à l'appelant s'il doit recharger le cache parsé en
  /// mémoire (`ParsedPlaylistService.reloadFromDisk`) — sans ça, l'app
  /// continuerait d'afficher l'ancienne liste jusqu'au prochain démarrage.
  static Future<({String? path, bool downloaded})> ensureDownloadedForAccount(
    StreamAccount acc, {
    bool respectTtl = true,
    bool force = false,
  }) {
    // revue 2026-09-11, D1A-02 — Sous le verrou du compte (cf. [_downloads]).
    _logWaitIfBusy(acc.id, acc.label);
    return _downloads.run(
      acc.id,
      () => _ensureDownloadedForAccountImpl(acc,
          respectTtl: respectTtl, force: force),
    );
  }

  static Future<({String? path, bool downloaded})>
      _ensureDownloadedForAccountImpl(
    StreamAccount acc, {
    required bool respectTtl,
    required bool force,
  }) async {
    final existing = await pathForAccountId(acc.id);
    final file = File(existing);
    final exists = await file.exists();
    final int length = exists ? await file.length() : 0;
    final Duration? age = exists
        ? DateTime.now().difference(await file.lastModified())
        : null;

    // §reloadKeep — [force] = rechargement demandé par l'utilisateur : on
    // télécharge SANS regarder l'existant, mais sans le supprimer non plus —
    // il reste la liste de secours si le serveur ne répond pas. C'est ce qui
    // remplace l'ancien « supprimer puis télécharger » de
    // `PlaylistReloadService`, qui laissait l'utilisateur sans liste sur échec.
    if (!force &&
        !needsDownload(
          exists: exists,
          lengthBytes: length,
          age: age,
          respectTtl: respectTtl,
        )) {
      return (path: existing, downloaded: false);
    }
    if (exists) {
      // §cacheKeep — Distinguer « vieille » de « trop petite pour être vraie » :
      // le second cas trahit une page d'erreur en cache, pas un TTL dépassé.
      final String pourquoi = length < minPlaylistBytes
          ? 'suspecte ($length octets < $minPlaylistBytes)'
          : 'périmée (${age!.inHours} h)';
      debugPrint('⏳ Playlist « ${acc.label} » $pourquoi → rafraîchissement.');
    }

    final url = acc.buildM3uUrl();
    if (url == null || url.isEmpty) {
      debugPrint("⚠️ ensureDownloadedForAccount: URL invalide pour ${acc.label}");
      return (path: null, downloaded: false);
    }

    // §23 — Tentative 1 : catalogue JSON direct. Si OK, on évite get.php.
    final jsonPath = await jsonPathForAccountId(acc.id);
    // revue 2026-09-11, D1A-01 — Lu AVANT la tentative : c'est ce catalogue-là
    // que le repli n'a pas le droit de détruire.
    final bool hasJsonSource = _hasCredibleJson(jsonPath);
    LoadFailureKind? failure;
    try {
      final res = await _downloadCatalog(acc, jsonPath);
      if (res.written) {
        await _deleteIfExists(await m3uPathForAccountId(acc.id));
        // §cacheKeep — `markStale`, PAS `invalidate` : ce service vient
        // d'écrire une nouvelle source, il n'a pas à supprimer le cache
        // analysé de l'ancienne. Si l'analyse qui suit échoue, ce cache est
        // tout ce qui reste entre l'utilisateur et un accueil vide.
        ParsedPlaylistService.markStale(acc.id);
        debugPrint('✅ Catalogue JSON téléchargé pour ${acc.label}.');
        return (path: jsonPath, downloaded: true);
      }
      failure = res.failure;
      // §catalogTruth — Un refus d'écriture est MOTIVÉ : on le nomme au journal
      // avant de décider, au lieu de laisser croire à un simple « pas de JSON ».
      debugPrint('⚠️ Catalogue JSON refusé pour ${acc.label} : '
          '${res.failure?.name ?? 'motif inconnu'}'
          '${res.detail == null ? '' : ' — ${res.detail}'}');
    } catch (e) {
      debugPrint('⚠️ Catalogue JSON ${acc.label} échec ($e)');
    }

    // revue 2026-09-11, D1A-01 — Le repli n'a lieu que s'il n'y a rien à
    // protéger (cf. `shouldFallbackToGetPhp`). Un panel saturé ou qui répond
    // `200 []` renverrait à `get.php` une page d'erreur : le catalogue sain
    // reste en place, et l'appelant sait qu'il n'y a rien de neuf.
    if (!shouldFallbackToGetPhp(failure: failure, hasJsonSource: hasJsonSource)) {
      debugPrint('🛑 §catalogTruth « ${acc.label} » : pas de repli get.php (${failure?.name ?? 'échec'}) — le catalogue JSON précédent est conservé.');
      return (path: exists ? existing : null, downloaded: false);
    }
    debugPrint('↪️ « ${acc.label} » : repli get.php.');

    // §23 — Tentative 2 : fallback get.php historique.
    final m3uPath = await m3uPathForAccountId(acc.id);
    final tempPath = '$m3uPath.part';
    try {
      await _fetchGetPhp(acc, url, tempPath);
      final temp = File(tempPath);
      // revue 2026-09-11, D1A-01 — La seule garde était « taille > 0 » : une
      // page d'erreur en `200` passait, était publiée et le `.json` sain
      // supprimé. Le contenu doit désormais ressembler à une liste AVANT le
      // renommage, et l'autre format n'est supprimé qu'APRÈS.
      if (!await _isCredibleM3uFile(temp)) {
        debugPrint('🛑 get.php « ${acc.label} » : le serveur n\'a pas rendu une liste → rien n\'est publié.');
        if (await temp.exists()) await temp.delete();
        // Échec : on garde le cache précédent s'il y en avait un — mieux vaut
        // une liste périmée qu'une liste vide.
        return (path: exists ? existing : null, downloaded: false);
      }
      await temp.rename(m3uPath);
      await _deleteIfExists(jsonPath);
      ParsedPlaylistService.markStale(acc.id); // §cacheKeep — cf. plus haut.
      debugPrint("✅ Playlist via get.php (fallback) pour ${acc.label}.");
      return (path: m3uPath, downloaded: true);
    } catch (e) {
      debugPrint("❌ ensureDownloadedForAccount(${acc.label}): $e");
      try {
        final temp = File(tempPath);
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      return (path: exists ? existing : null, downloaded: false);
    }
  }

  /// §secondaryRefresh — Contrôle de fraîcheur + rechargement mémoire pour UN
  /// compte, quel qu'il soit. Silencieux (aucune exception ne remonte), pensé
  /// pour un appel en arrière-plan : la home se met à jour d'elle-même via
  /// `ParsedPlaylistService.version` quand le rechargement aboutit.
  ///
  /// Retourne `true` si la playlist a réellement été renouvelée.
  ///
  /// Utile après une bascule de compte principal : `setCurrentAccount` n'écrit
  /// qu'une préférence et ne déclenche aucun téléchargement — sans ça, le
  /// nouveau principal n'était confronté au TTL qu'au redémarrage suivant.
  static Future<bool> refreshIfStale(StreamAccount acc) async {
    try {
      final res = await ensureDownloadedForAccount(acc);
      if (!res.downloaded || res.path == null) return false;
      await ParsedPlaylistService.reloadFromDisk(acc.id, acc.label, res.path!);
      debugPrint('🔄 §secondaryRefresh : « ${acc.label} » rafraîchie.');
      return true;
    } catch (e) {
      debugPrint('⚠️ refreshIfStale(${acc.label}) : $e');
      return false;
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<String> _buildUrlForCurrentAccount() async {
    final acc = await StreamAccountService.getCurrentAccount();
    // Normalement, playlistPath() a déjà vérifié ça, mais c'est une sécurité.
    if (acc == null) throw const HttpException("Aucun compte actif sélectionné.");
    final url = acc.buildM3uUrl();
    if (url == null || url.isEmpty) {
      throw HttpException("L'URL de la playlist pour le compte '${acc.label}' est invalide. Veuillez vérifier sa configuration.");
    }
    return url;
  }

  static Future<String> downloadCurrentM3U() async =>
      (await downloadCurrentM3UResult()).path;

  /// revue 2026-09-11, D1A-01 — Comme [downloadCurrentM3U], mais dit aussi si
  /// une source NEUVE a été écrite.
  ///
  /// ⚠️ Nécessaire depuis que le repli `get.php` peut être refusé : quand le
  /// panel refuse le catalogue JSON et qu'un catalogue sain existe, on rend le
  /// chemin EXISTANT (le démarrage continue sur la liste d'hier plutôt que de
  /// s'arrêter sur une erreur) — mais un rechargement demandé par
  /// l'utilisateur ne doit pas l'annoncer « rechargé » (`PlaylistReloadService`
  /// lit [downloaded], comme il le faisait déjà pour les secondaires).
  static Future<({String path, bool downloaded})>
      downloadCurrentM3UResult() async {
    // revue 2026-09-11, D1A-02 — Sous le verrou du compte (cf. [_downloads]).
    final String key = await _currentAccountKey();
    _logWaitIfBusy(key, key);
    return _downloads.run(key, _downloadCurrentM3UImpl);
  }

  /// Corps de [downloadCurrentM3UResult], SANS le verrou : l'appelant le
  /// tient déjà (`_getOrDownloadPlaylist`) ou le prend juste avant.
  static Future<({String path, bool downloaded})>
      _downloadCurrentM3UImpl() async {
    String url = '';
    String m3uPath = '';
    String tempPath = '';

    try {
      url = await _buildUrlForCurrentAccount();
      final acc = await StreamAccountService.getCurrentAccount();

      // §23 — TENTATIVE 1 : catalogue JSON direct (`player_api.php?action=…`).
      // Plus fiable que `get.php` qui plante sur certains panels (PHP timeout
      // sur grosse génération) ET sans perte de métadonnées. On dégrade vers
      // `get.php` (TENTATIVE 2) si l'API échoue. Voir `XtreamCatalogService`.
      if (acc != null) {
        final jsonPath = await jsonPathForAccountId(acc.id);
        // revue 2026-09-11, D1A-01 — Lu AVANT la tentative (cf. plus bas).
        final bool hasJsonSource = _hasCredibleJson(jsonPath);
        LoadFailureKind? failure;
        try {
          final res = await _downloadCatalog(acc, jsonPath);
          if (res.written) {
            await _deleteIfExists(await m3uPathForAccountId(acc.id));
            debugPrint('✅ Catalogue JSON téléchargé '
                '(${await File(jsonPath).length()} octets).');
            // §cacheKeep — La source est neuve, la copie en mémoire est
            // périmée : `markStale`. Supprimer le cache analysé ici, c'était
            // parier que l'analyse suivante réussirait toujours.
            ParsedPlaylistService.markStale(acc.id);
            return (path: jsonPath, downloaded: true);
          }
          failure = res.failure;
          // §catalogTruth — Le refus a un motif : le dire.
          debugPrint('⚠️ JSON API refusée : '
              '${res.failure?.name ?? 'motif inconnu'}'
              '${res.detail == null ? '' : ' — ${res.detail}'}');
        } catch (e) {
          debugPrint('⚠️ JSON API a échoué ($e)');
        }
        // revue 2026-09-11, D1A-01 — Pas de repli quand un catalogue sain
        // existe et que le refus est motivé (saturé, amputé, vide) : on rend
        // le catalogue EXISTANT, sans rien détruire. (Si le repli est refusé,
        // c'est qu'un `.json` crédible existe : le chemin est donc sûr.)
        if (!shouldFallbackToGetPhp(
            failure: failure, hasJsonSource: hasJsonSource)) {
          debugPrint('🛑 §catalogTruth : pas de repli get.php (${failure?.name ?? 'échec'}) — le catalogue JSON précédent est conservé.');
          return (path: jsonPath, downloaded: false);
        }
        debugPrint('↪️ Repli sur get.php.');
      }

      // §23 — TENTATIVE 2 : fallback historique sur `get.php`.
      // Plus fragile mais nécessaire pour les panels qui n'exposent pas la
      // JSON API ou pour les comptes non-Xtream (Flussonic, M3U custom…).
      m3uPath = acc != null
          ? await m3uPathForAccountId(acc.id)
          : await playlistPath();
      tempPath = '$m3uPath.part';
      await _fetchGetPhp(acc, url, tempPath);

      final tempFile = File(tempPath);
      // revue 2026-09-11, D1A-01 — Validé par le CONTENU avant d'être publié
      // (une page d'erreur en `200` n'est pas une liste) ; l'autre format
      // n'est supprimé qu'après le renommage.
      if (!await _isCredibleM3uFile(tempFile)) {
        // Le `.part` refusé ne doit pas traîner jusqu'au prochain
        // téléchargement : la branche `on HttpException` ci-dessous relève
        // sans rien nettoyer.
        await _deleteIfExists(tempPath);
        throw HttpException(L10n.current.playlistNotAList);
      }

      await tempFile.rename(m3uPath);
      if (acc != null) {
        await _deleteIfExists(await jsonPathForAccountId(acc.id));
      }
      debugPrint("✅ Playlist téléchargée via get.php (fallback) et mise en cache.");

      // §cacheKeep — Marquer la mémoire périmée : le prochain loadActive()
      // re-parsera le fichier. Le cache analysé, lui, RESTE sur disque — il est
      // le filet si ce re-parse n'aboutit pas.
      if (acc != null) ParsedPlaylistService.markStale(acc.id);

      return (path: m3uPath, downloaded: true);
    } on DioException catch (e) {
      if (tempPath.isNotEmpty) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }

      // §userError — Ce switch dupliquait celui de `describeError()`, en moins
      // sûr : sa branche par défaut affichait `e.message` BRUT, sans passer
      // par `sanitizeForLog` — un `DioException` peut embarquer l'URL de
      // requête AVEC les identifiants Xtream (§logHygiene). Constaté sur
      // appareil réel : `e.message` était `null` pour ce type d'exception, ce
      // qui produisait littéralement « Erreur réseau inconnue : null » —
      // `describeError` sait déjà déballer `e.error` pour ce cas précis
      // (`DioExceptionType.unknown`) au lieu d'afficher le champ vide.
      throw HttpException(describeError(e));
    } on HttpException {
      rethrow;
    } catch (e) {
      // §userError — Même défaut que la branche `DioException` ci-dessus : ce
      // repli attrape aussi bien une `SocketException` brute (ex. « Connection
      // reset by peer », jamais traduite ni passée au filet §logHygiene) qu'un
      // Dio wrapping différent. `describeError` sait déjà classer les deux.
      throw HttpException(describeError(e));
    }
  }
}
