import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

  static String _mo(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
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
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo'
      : '${(bytes / 1024).toStringAsFixed(0)} Ko';
}
