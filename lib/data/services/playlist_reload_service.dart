import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/stream_account.dart';
import 'parsed_playlist_service.dart';
import 'playlist_service.dart';

/// §reloadAll — Rechargement FORCÉ de la playlist d'un compte.
///
/// **Pourquoi ce service existe** : la logique vivait dans
/// `_AccountCardState._reload()`, donc dans un widget. Le rechargement en lot
/// devait soit la dupliquer, soit piloter des cartes une par une — deux
/// mauvaises options. Extraite ici, elle sert les deux chemins sans divergence
/// possible.
///
/// ⚠️ **À ne pas confondre avec `PlaylistService.refreshIfStale()`**
/// (§secondaryRefresh), qui respecte le TTL de 24 h. Ici c'est un **forçage
/// explicite** : on supprime le cache avant de retélécharger, parce que
/// l'utilisateur a demandé un rechargement, pas une vérification.
abstract final class PlaylistReloadService {
  /// Recharge un compte. Lève en cas d'échec — l'appelant décide quoi en faire
  /// (une carte affiche un snackbar, un lot note et continue).
  ///
  /// ⚠️ [isPriority] change le CHEMIN de téléchargement, et cette distinction
  /// doit être conservée : le compte principal passe par `downloadCurrentM3U()`,
  /// qui produit des messages d'erreur précis ; les secondaires par
  /// `ensureDownloadedForAccount()`. Uniformiser ferait perdre le diagnostic
  /// sur le compte qui compte le plus.
  static Future<void> reloadAccount(
    StreamAccount account, {
    required bool isPriority,
  }) async {
    await PlaylistService.deleteForAccountId(account.id);

    final String? newPath = isPriority
        ? await PlaylistService.downloadCurrentM3U()
        : (await PlaylistService.ensureDownloadedForAccount(account)).path;

    if (newPath == null) {
      throw const HttpException(
          'Téléchargement impossible (vérifie l\'URL ou la connexion).');
    }

    await ParsedPlaylistService.reloadFromDisk(
      account.id,
      account.label,
      newPath,
    );
    debugPrint('✅ §reloadAll — « ${account.label} » rechargée');
  }

  /// Âge du cache d'un compte, ou `null` s'il n'y en a pas.
  ///
  /// Sert à ne demander confirmation que pour les listes RÉCENTES : recharger
  /// une liste vieille de trois jours n'appelle aucune question.
  static Future<Duration?> cacheAge(String accountId) async {
    try {
      final path = await PlaylistService.pathForAccountId(accountId);
      final file = File(path);
      if (!await file.exists()) return null;
      return DateTime.now().difference(await file.lastModified());
    } catch (_) {
      return null;
    }
  }
}

/// §reloadAll — Bilan d'un rechargement en lot.
@immutable
class ReloadBatchResult {
  final List<String> succeeded;

  /// Libellés des comptes en échec, avec leur raison.
  final Map<String, String> failed;

  const ReloadBatchResult({required this.succeeded, required this.failed});

  int get total => succeeded.length + failed.length;
  bool get allOk => failed.isEmpty;

  /// Phrase de bilan, pensée pour un snackbar.
  ///
  /// ⚠️ Nomme les listes en échec : « 1 échec » sans dire laquelle oblige à
  /// rouvrir chaque carte pour trouver le coupable.
  String get summary {
    if (failed.isEmpty) {
      return '✅ ${succeeded.length} liste(s) rechargée(s)';
    }
    if (succeeded.isEmpty) {
      return '❌ Aucune liste rechargée — ${failed.keys.join(', ')}';
    }
    return '⚠️ ${succeeded.length} rechargée(s), '
        '${failed.length} en échec : ${failed.keys.join(', ')}';
  }
}
