import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../feature/downloads/logic/partial_sweep.dart';
import '../../l10n/l10n_ext.dart';

/// §acctPurge — Le ménage du stockage : ce qui n'appartient plus à personne.
///
/// ## Le constat qui a créé ce fichier (2026-09-02, sur le téléphone de test)
///
/// L'application détenait **~290 Mo de fichiers rattachés à des comptes
/// supprimés** : un `playlist_….m3u` de **217 Mo** datant du 24 mai, un
/// catalogue JSON de 32 Mo d'août, et 37 Mo de caches parsés. Cause :
/// `StreamAccountService.deleteAccount` effaçait la fiche du compte en stockage
/// sécurisé et l'index — **jamais ses fichiers**.
///
/// Personne ne pouvait le voir : la page « À propos » additionne le disque des
/// comptes VIVANTS (elle annonçait 61 Mo pendant que l'app en occupait 350), et
/// rien dans l'interface ne parle des fichiers orphelins. Chaque compte essayé
/// puis supprimé laissait sa playlist derrière lui, à vie.
///
/// ## Deux mécanismes, pas un
///
/// 1. [purgeAccount] — le correctif à la SOURCE, appelé par `deleteAccount` :
///    supprimer un compte supprime ses fichiers. Empêche la dette de renaître.
/// 2. [sweepOrphans] — le rattrapage, pour les installations qui portent DÉJÀ
///    des orphelins. Un correctif de source ne nettoie que l'avenir.
///
/// ## ⚠️ Le garde-fou à ne JAMAIS retirer
///
/// [sweepOrphans] supprime tout fichier dont l'identifiant de compte n'est pas
/// dans la liste fournie. Si cette liste arrive **vide** parce que
/// `FlutterSecureStorage` a hoqueté au démarrage, le balayage effacerait
/// **toutes les playlists de l'utilisateur** — un incident bien pire que les
/// 290 Mo qu'il répare.
///
/// D'où [allowEmptyAccountList], **faux par défaut** : le balayage automatique
/// du démarrage refuse de tourner sur une liste vide. Seule une action
/// explicite de l'utilisateur (le bouton d'Optimisation, où il voit de ses yeux
/// qu'il n'a aucun compte) peut passer `true`.
class StorageJanitor {
  StorageJanitor._();

  /// Préfixe des fichiers playlist téléchargés (`PlaylistService`).
  ///
  /// ⚠️ Ces quatre constantes DUPLIQUENT la convention de nommage des services
  /// propriétaires — un balayeur travaille sur des motifs de noms, pas sur des
  /// chemins par compte, donc il ne peut pas les leur demander. Le test
  /// `test/storage_janitor_test.dart` vérifie qu'elles restent alignées sur les
  /// chemins réellement produits : si un service renomme ses fichiers, c'est ce
  /// test qui prévient, pas un utilisateur qui perd sa liste.
  static const String playlistPrefix = 'playlist_';
  static const List<String> playlistExtensions = ['.json', '.m3u'];

  /// Préfixe du cache parsé (`ParsedPlaylistService`).
  static const String parsedPrefix = 'parsed_playlist_';
  static const String parsedExtension = '.json.gz';

  /// §engineVendor — Reliquats de `media_kit`/libmpv, moteur retiré le
  /// 2026-09-01. Le plugin n'existe plus, donc plus rien ne les crée ni ne les
  /// relit ; 267 fichiers traînaient encore sur l'appareil de test.
  static const String legacyEnginePrefix = 'com.alexmercerind.media_kit.';

  /// §dlPartSweep — Sous-dossier public des films téléchargés
  /// (`/Movies/AetherStream/`). Même valeur que `MediaStore.appFolder`
  /// (`main.dart`) et que `StorageService._appName`.
  static const String publicMediaFolder = 'AetherStream';

  // ── Emplacements ──────────────────────────────────────────────────────────
  // Android : documents = `<data>/app_flutter` (playlists téléchargées),
  //           support   = `<data>/files`      (caches parsés + reliquats).

  static Future<Directory> _documentsDir() => getApplicationDocumentsDirectory();
  static Future<Directory> _supportDir() => getApplicationSupportDirectory();

  /// Identifiant de compte porté par [fileName], ou `null` si le fichier
  /// n'appartient à aucun compte (police, base d'images, `flutter_assets`…).
  @visibleForTesting
  static String? accountIdOf(String fileName) {
    if (fileName.startsWith(parsedPrefix)) {
      if (!fileName.endsWith(parsedExtension)) return null;
      final id = fileName.substring(
          parsedPrefix.length, fileName.length - parsedExtension.length);
      return id.isEmpty ? null : id;
    }
    if (fileName.startsWith(playlistPrefix)) {
      for (final ext in playlistExtensions) {
        if (!fileName.endsWith(ext)) continue;
        final id = fileName.substring(
            playlistPrefix.length, fileName.length - ext.length);
        return id.isEmpty ? null : id;
      }
    }
    return null;
  }

  // ── 1. Correctif de source ────────────────────────────────────────────────

  /// Supprime TOUS les fichiers d'un compte. Appelé par
  /// `StreamAccountService.deleteAccount` — c'est ce qui manquait.
  ///
  /// Renvoie le nombre d'octets libérés. Ne lève jamais : perdre un compte à
  /// cause d'une erreur de système de fichiers serait pire que garder 200 Mo.
  static Future<int> purgeAccount(String accountId) async {
    var freed = 0;
    try {
      final docs = await _documentsDir();
      final support = await _supportDir();
      final targets = <File>[
        for (final ext in playlistExtensions)
          File('${docs.path}/$playlistPrefix$accountId$ext'),
        File('${support.path}/$parsedPrefix$accountId$parsedExtension'),
      ];
      for (final f in targets) {
        freed += await _deleteIfExists(f);
      }
      if (freed > 0) {
        debugPrint('🧹 §acctPurge — compte $accountId : '
            '${_mo(freed)} libérés à la suppression');
      }
    } catch (e) {
      debugPrint('⚠️ §acctPurge — purge du compte $accountId : $e');
    }
    return freed;
  }

  // ── 2. Rattrapage ─────────────────────────────────────────────────────────

  /// Supprime les fichiers dont le compte n'existe plus, plus les reliquats du
  /// moteur retiré.
  ///
  /// [knownAccountIds] doit être la liste COMPLÈTE des comptes existants. Voir
  /// l'avertissement en tête de classe pour [allowEmptyAccountList].
  static Future<StorageSweepResult> sweepOrphans({
    required Set<String> knownAccountIds,
    bool allowEmptyAccountList = false,
    bool dryRun = false,
  }) async {
    if (knownAccountIds.isEmpty && !allowEmptyAccountList) {
      // Ni erreur ni exception : c'est un refus délibéré, et il doit se voir
      // dans le journal servi par la console web (§tvLogs).
      debugPrint('🛑 §acctPurge — balayage REFUSÉ : aucune liste de comptes. '
          'Un stockage sécurisé qui hoquette ne doit pas effacer les listes.');
      return const StorageSweepResult.refused();
    }

    final files = <File>[];
    var bytes = 0;
    try {
      final docs = await _documentsDir();
      final support = await _supportDir();

      for (final dir in [docs, support]) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;

          final isLegacyEngine = name.startsWith(legacyEnginePrefix);
          final owner = accountIdOf(name);
          final isOrphan = owner != null && !knownAccountIds.contains(owner);
          if (!isLegacyEngine && !isOrphan) continue;

          files.add(entity);
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }

      if (!dryRun) {
        for (final f in files) {
          await _deleteIfExists(f);
        }
      }
    } catch (e) {
      debugPrint('⚠️ §acctPurge — balayage : $e');
    }

    final result = StorageSweepResult(fileCount: files.length, bytes: bytes);
    if (files.isNotEmpty) {
      debugPrint('🧹 §acctPurge — ${dryRun ? 'récupérables' : 'libérés'} : '
          '${_mo(bytes)} sur ${files.length} fichier(s) sans propriétaire');
    }
    return result;
  }

  /// Ce que le balayage libérerait, sans rien supprimer — pour l'affichage.
  static Future<StorageSweepResult> preview({
    required Set<String> knownAccountIds,
    bool allowEmptyAccountList = false,
  }) =>
      sweepOrphans(
        knownAccountIds: knownAccountIds,
        allowEmptyAccountList: allowEmptyAccountList,
        dryRun: true,
      );

  // ── 3. Les partiels de téléchargement (§dlPartSweep) ─────────────────────

  /// Dossier public des films téléchargés, ou `null` s'il est introuvable.
  ///
  /// ⚠️ Volontairement SANS `permission_handler` : ce balayage tourne au
  /// démarrage, et rien ne justifie d'y faire surgir une demande de permission.
  /// Si le dossier n'est pas lisible, la liste échoue et on l'ignore — les
  /// partiels du cache privé, eux, restent toujours accessibles.
  static Future<Directory?> _publicMoviesDir() async {
    try {
      final dirs =
          await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs == null || dirs.isEmpty) return null;
      final String root = dirs.first.path.split('/Android/').first;
      return Directory('$root/Movies/$publicMediaFolder');
    } catch (e) {
      debugPrint('⚠️ §dlPartSweep — dossier public introuvable : $e');
      return null;
    }
  }

  /// Dossier des fichiers partiels, sous le cache de l'application.
  ///
  /// ⚠️ **Duplique la résolution de `download_initiator._getTempDirectory`** —
  /// même raison que les préfixes de playlist ci-dessus : un balayeur travaille
  /// sur des emplacements, il ne peut pas les demander à celui qui écrit. Le
  /// NOM du dossier, lui, a une définition unique ([kDownloadTmpDirName]), et
  /// `test/download_partial_sweep_test.dart` vérifie l'accord.
  static Future<Directory?> _downloadTmpDir() async {
    try {
      final external = await getExternalCacheDirectories();
      final String base = (external != null && external.isNotEmpty)
          ? external.first.path
          : (await getTemporaryDirectory()).path;
      return Directory(downloadTmpPath(base));
    } catch (e) {
      debugPrint('⚠️ §dlPartSweep — cache de téléchargement introuvable : $e');
      return null;
    }
  }

  /// Supprime les fichiers partiels qu'aucune tâche ne peut plus reprendre.
  ///
  /// [liveTempPaths] doit être l'ensemble COMPLET des `tempPath` des tâches
  /// connues, **tous statuts confondus** : `failed` et `canceled` désignent des
  /// transferts que « Relancer » reprend à l'octet près.
  ///
  /// ## ⚠️ Le garde-fou, identique à celui de [sweepOrphans]
  ///
  /// Si la liste des tâches n'a pas pu être relue (préférences qui hoquettent),
  /// [liveTempPaths] arrive **vide** et TOUT devient orphelin — y compris un
  /// téléchargement de plusieurs gigaoctets en attente de reprise. Le balayage
  /// automatique refuse donc de tourner sur un ensemble vide ; seule une action
  /// explicite de l'utilisateur peut passer [allowEmptyTaskList].
  static Future<StorageSweepResult> sweepDownloadPartials({
    required Set<String> liveTempPaths,
    bool allowEmptyTaskList = false,
    Duration minimumAge = defaultMinimumAge,
    bool dryRun = false,
    DateTime? now,
    // ⚠️ Réservés aux tests : `getExternalCacheDirectories` et
    // `getExternalStorageDirectories` lèvent hors Android AVANT d'atteindre le
    // canal, donc aucun simulacre ne peut les couvrir. Injecter les dossiers
    // est le seul moyen d'exercer le balayage sur de vrais fichiers.
    @visibleForTesting Directory? tmpDirectory,
    @visibleForTesting Directory? publicDirectory,
  }) async {
    if (liveTempPaths.isEmpty && !allowEmptyTaskList) {
      debugPrint("🛑 §dlPartSweep — balayage REFUSÉ : aucune tâche connue. Une liste qui n'a pas pu être relue ne doit pas effacer des reprises en attente.");
      return const StorageSweepResult.refused();
    }

    final List<PartialFile> orphans = <PartialFile>[];
    try {
      final Directory? tmp = tmpDirectory ?? await _downloadTmpDir();
      final Directory? public = publicDirectory ?? await _publicMoviesDir();

      orphans.addAll(orphanPartials(
        inPrivateCache: await _scan(tmp),
        inPublicFolder: await _scan(public),
        liveTempPaths: liveTempPaths.map(_slash).toSet(),
        now: now ?? DateTime.now(),
        minimumAge: minimumAge,
      ));

      if (!dryRun) {
        for (final PartialFile f in orphans) {
          await _deleteIfExists(File(f.path));
        }
      }
    } catch (e) {
      debugPrint('⚠️ §dlPartSweep — balayage : $e');
    }

    final int bytes =
        orphans.fold<int>(0, (int acc, PartialFile f) => acc + f.bytes);
    if (orphans.isNotEmpty) {
      debugPrint('🧹 §dlPartSweep — ${dryRun ? 'récupérables' : 'libérés'} : ${_mo(bytes)} sur ${orphans.length} partiel(s) abandonné(s)');
      for (final PartialFile f in orphans) {
        debugPrint('   • ${f.fileName} (${_mo(f.bytes)})');
      }
    }
    return StorageSweepResult(fileCount: orphans.length, bytes: bytes);
  }

  /// Sépare toujours par `/`, quelle que soit la plateforme.
  ///
  /// ⚠️ Appliqué aux DEUX côtés de la comparaison (fichiers trouvés ET
  /// `tempPath` des tâches) : normaliser un seul côté ferait passer un partiel
  /// VIVANT pour un orphelin sous Windows, où tournent les tests.
  /// ⚠️ L'antislash est construit par son code : écrit en littéral, il ne
  /// survit pas à la couche d'édition (constaté trois fois sur ce projet).
  static final String _sep = String.fromCharCode(92);
  static String _slash(String path) => path.replaceAll(_sep, '/');

  /// Le contenu d'un dossier, ou rien s'il est absent ou illisible.
  static Future<List<PartialFile>> _scan(Directory? dir) async {
    if (dir == null) return const <PartialFile>[];
    final List<PartialFile> out = <PartialFile>[];
    try {
      if (!await dir.exists()) return out;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final FileStat stat = await entity.stat();
          out.add(PartialFile(
            path: _slash(entity.path),
            bytes: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {
          // Un fichier illisible ne doit pas faire échouer le balayage entier.
        }
      }
    } catch (e) {
      debugPrint('⚠️ §dlPartSweep — lecture de ${dir.path} : $e');
    }
    return out;
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  static Future<int> _deleteIfExists(File f) async {
    try {
      if (!await f.exists()) return 0;
      final size = await f.length();
      await f.delete();
      return size;
    } catch (_) {
      return 0;
    }
  }

  /// §acctDeleteTruth — Ce que la suppression d'un compte va effacer, en
  /// octets, **sans rien supprimer**. Sert à l'annoncer AVANT de le faire :
  /// « cette action est définitive » ne disait pas qu'elle emportait jusqu'à
  /// 217 Mo de liste téléchargée (mesuré, §acctPurge).
  ///
  /// ⚠️ Même liste de cibles que [purgeAccount] — les deux doivent rester
  /// alignées, sinon le chiffre annoncé n'est pas celui qui part.
  static Future<int> accountFootprint(String accountId) async {
    var bytes = 0;
    try {
      final docs = await _documentsDir();
      final support = await _supportDir();
      final targets = <File>[
        for (final ext in playlistExtensions)
          File('${docs.path}/$playlistPrefix$accountId$ext'),
        File('${support.path}/$parsedPrefix$accountId$parsedExtension'),
      ];
      for (final f in targets) {
        try {
          if (await f.exists()) bytes += await f.length();
        } catch (_) {
          // Un fichier illisible ne doit pas empêcher d'annoncer les autres.
        }
      }
    } catch (e) {
      debugPrint('⚠️ §acctPurge — empreinte du compte $accountId : $e');
    }
    return bytes;
  }

  /// Taille lisible. Passe en Ko sous le mégaoctet : « 0.0 Mo » pour un cache
  /// de 300 Ko donnerait l'impression qu'il n'y a rien à perdre.
  static String humanBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return L10n.current
          .sizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
    }
    if (bytes >= 1024) {
      return L10n.current.sizeKilobytes('${(bytes / 1024).round()}');
    }
    return L10n.current.sizeBytes('$bytes');
  }

  static String _mo(int bytes) => humanBytes(bytes);
}

/// Bilan d'un balayage. [refused] distingue « rien à faire » de « je n'ai pas
/// osé » — les deux libèrent 0 octet, mais seul le second est un signal.
@immutable
class StorageSweepResult {
  final int fileCount;
  final int bytes;
  final bool refused;

  const StorageSweepResult({required this.fileCount, required this.bytes})
      : refused = false;

  const StorageSweepResult.refused()
      : fileCount = 0,
        bytes = 0,
        refused = true;

  bool get isEmpty => fileCount == 0;

  String get label => bytes >= 1024 * 1024
      ? L10n.current.sizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1))
      : L10n.current.sizeKilobytes((bytes / 1024).toStringAsFixed(0));
}
