import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import '../../core/utils/network.dart';
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

  static Future<void> deleteExisting() async {
    try {
      final acc = await StreamAccountService.getCurrentAccount();
      if (acc != null) await deleteForAccountId(acc.id);
    } catch (_) {}
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
  static Future<String> getOrDownloadPlaylist({
    void Function()? onDownloadStart,
  }) async {
    final path = await playlistPath();
    final file = File(path);

    if (await file.exists()) {
      final lastModified = await file.lastModified();
      if (DateTime.now().difference(lastModified) < playlistCacheDuration) {
        debugPrint(
            "✅ Playlist trouvée en cache et encore valide. Pas de téléchargement.");
        return path;
      } else {
        debugPrint(
            "⏳ Playlist trouvée en cache mais périmée. Retéléchargement...");
      }
    } else {
      debugPrint("ℹ️ Aucune playlist en cache. Téléchargement initial...");
    }
    onDownloadStart?.call();
    return downloadCurrentM3U();
  }

  /// §secondaryRefresh — Décision « faut-il (re)télécharger ? », isolée en
  /// fonction PURE pour être testable sans système de fichiers.
  ///
  /// [age] est l'âge du cache (`null` si le fichier n'existe pas).
  /// [respectTtl] à `false` = on ne télécharge que si le fichier manque
  /// (ancien comportement de [ensureDownloadedForAccount], conservé pour les
  /// appelants qui veulent seulement *peupler* un compte).
  @visibleForTesting
  static bool needsDownload({
    required bool exists,
    required int lengthBytes,
    required Duration? age,
    bool respectTtl = true,
  }) {
    if (!exists || lengthBytes <= 0) return true;
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
  }) async {
    final existing = await pathForAccountId(acc.id);
    final file = File(existing);
    final exists = await file.exists();
    final int length = exists ? await file.length() : 0;
    final Duration? age = exists
        ? DateTime.now().difference(await file.lastModified())
        : null;

    if (!needsDownload(
      exists: exists,
      lengthBytes: length,
      age: age,
      respectTtl: respectTtl,
    )) {
      return (path: existing, downloaded: false);
    }
    if (exists) {
      debugPrint('⏳ Playlist « ${acc.label} » périmée '
          '(${age!.inHours} h) → rafraîchissement.');
    }

    final url = acc.buildM3uUrl();
    if (url == null || url.isEmpty) {
      debugPrint("⚠️ ensureDownloadedForAccount: URL invalide pour ${acc.label}");
      return (path: null, downloaded: false);
    }

    // §23 — Tentative 1 : catalogue JSON direct. Si OK, on évite get.php.
    try {
      final jsonPath = await jsonPathForAccountId(acc.id);
      if (await XtreamCatalogService.downloadCatalog(acc, jsonPath)) {
        await _deleteIfExists(await m3uPathForAccountId(acc.id));
        ParsedPlaylistService.invalidate(acc.id);
        debugPrint('✅ Catalogue JSON téléchargé pour ${acc.label}.');
        return (path: jsonPath, downloaded: true);
      }
    } catch (e) {
      debugPrint('⚠️ Catalogue JSON ${acc.label} échec ($e), fallback get.php');
    }

    // §23 — Tentative 2 : fallback get.php historique.
    final m3uPath = await m3uPathForAccountId(acc.id);
    final tempPath = '$m3uPath.part';
    try {
      final dio = await NetworkUtils.buildDio(url);
      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final temp = File(tempPath);
      if (!await temp.exists() || await temp.length() == 0) {
        if (await temp.exists()) await temp.delete();
        // Échec : on garde le cache précédent s'il y en avait un — mieux vaut
        // une liste périmée qu'une liste vide.
        return (path: exists ? existing : null, downloaded: false);
      }
      await temp.rename(m3uPath);
      await _deleteIfExists(await jsonPathForAccountId(acc.id));
      ParsedPlaylistService.invalidate(acc.id);
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

  static Future<String> downloadCurrentM3U() async {
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
        try {
          final jsonPath = await jsonPathForAccountId(acc.id);
          if (await XtreamCatalogService.downloadCatalog(acc, jsonPath)) {
            await _deleteIfExists(await m3uPathForAccountId(acc.id));
            debugPrint('✅ Catalogue JSON téléchargé '
                '(${await File(jsonPath).length()} octets).');
            ParsedPlaylistService.invalidate(acc.id);
            return jsonPath;
          }
          debugPrint('⚠️ JSON API n\'a rien retourné, fallback sur get.php');
        } catch (e) {
          debugPrint('⚠️ JSON API a échoué ($e), fallback sur get.php');
        }
      }

      // §23 — TENTATIVE 2 : fallback historique sur `get.php`.
      // Plus fragile mais nécessaire pour les panels qui n'exposent pas la
      // JSON API ou pour les comptes non-Xtream (Flussonic, M3U custom…).
      m3uPath = acc != null
          ? await m3uPathForAccountId(acc.id)
          : await playlistPath();
      tempPath = '$m3uPath.part';
      final dio = await NetworkUtils.buildDio(url);

      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
        ),
      );

      final tempFile = File(tempPath);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw const HttpException("Le serveur a renvoyé un fichier vide. Vérifiez l'URL de la playlist.");
      }

      await tempFile.rename(m3uPath);
      if (acc != null) {
        await _deleteIfExists(await jsonPathForAccountId(acc.id));
      }
      debugPrint("✅ Playlist téléchargée via get.php (fallback) et mise en cache.");

      // Invalider le cache parsé — le prochain loadActive() re-parsera le fichier.
      if (acc != null) ParsedPlaylistService.invalidate(acc.id);

      return m3uPath;
    } on DioException catch (e) {
      if (tempPath.isNotEmpty) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }

      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw HttpException("Le serveur a mis trop de temps à répondre (timeout).\nVérifiez votre connexion ou l'adresse du serveur.");
        case DioExceptionType.badResponse:
          final statusCode = e.response?.statusCode;
          if (statusCode != null) {throw HttpException("Le serveur a répondu avec une erreur : $statusCode.\nVérifiez l'URL de la playlist.");
          }
          throw HttpException("Réponse invalide du serveur. Vérifiez l'URL de la playlist.");
        case DioExceptionType.connectionError:
          throw const HttpException("Erreur de connexion.\nAssurez-vous d'être connecté à internet et que l'hôte est accessible.");
        case DioExceptionType.cancel:
          throw const HttpException("Le téléchargement a été annulé.");
        default:
          throw HttpException("Erreur réseau inconnue : ${e.message}");
      }
    } on HttpException {
      rethrow;
    } catch (e) {
      throw HttpException("Une erreur inattendue est survenue : ${e.toString()}");
    }
  }
}
