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
/// explicite** : on retélécharge sans regarder l'âge du cache, parce que
/// l'utilisateur a demandé un rechargement, pas une vérification.
abstract final class PlaylistReloadService {
  /// Seuil sous lequel un rechargement demande confirmation : une liste plus
  /// jeune que ça est probablement déjà à jour, et le rechargement coûte un
  /// téléchargement complet + un parsing.
  static const Duration confirmBelow = Duration(hours: 24);

  /// Recharge un compte. Lève en cas d'échec — l'appelant décide quoi en faire
  /// (une carte affiche un snackbar, un lot note et continue).
  ///
  /// ⚠️ [isPriority] change le CHEMIN de téléchargement, et cette distinction
  /// doit être conservée : le compte principal passe par `downloadCurrentM3U()`,
  /// qui produit des messages d'erreur précis ; les secondaires par
  /// `ensureDownloadedForAccount()`. Uniformiser ferait perdre le diagnostic
  /// sur le compte qui compte le plus.
  ///
  /// §reloadKeep — **On ne supprime PLUS l'ancienne liste avant de télécharger.**
  /// L'ancien code faisait `deleteForAccountId` en première ligne : sur un
  /// échec réseau (serveur injoignable, timeout, 500 muet), l'utilisateur se
  /// retrouvait SANS liste du tout — et ça touchait les trois chemins (↻ de
  /// l'accueil, « Recharger » d'une carte, « Tout recharger »). Or les deux
  /// téléchargeurs sont déjà atomiques : ils écrivent dans un `.part`, ne
  /// renomment qu'après succès, effacent eux-mêmes l'autre format
  /// (json ↔ m3u) et invalident le cache parsé. Supprimer avant n'apportait
  /// donc rien, et coûtait la liste en cas d'échec. Mieux vaut une liste
  /// périmée qu'une liste vide.
  static Future<void> reloadAccount(
    StreamAccount account, {
    required bool isPriority,
  }) async {
    final String? newPath;
    if (isPriority) {
      newPath = await PlaylistService.downloadCurrentM3U();
    } else {
      // ⚠️ `force: true`, pas `respectTtl: false` : ce dernier ne télécharge
      // que si le fichier MANQUE — c'est-à-dire jamais, puisqu'on ne le
      // supprime plus.
      final res = await PlaylistService.ensureDownloadedForAccount(
        account,
        force: true,
      );
      // ⚠️ Ne lève jamais : sur échec il rend l'ANCIEN chemin (liste conservée,
      // c'est le but) avec `downloaded: false`. Sans ce test, on re-parserait
      // l'ancienne liste et on annoncerait « rechargée » à tort.
      newPath = res.downloaded ? res.path : null;
    }

    if (newPath == null) {
      throw const HttpException(
          'Téléchargement impossible (vérifie l\'URL ou la connexion).');
    }

    // §cacheKeep — Le retour était IGNORÉ. `reloadFromDisk` rend `null` quand
    // l'analyse échoue : on journalisait alors « ✅ rechargée » sur une liste
    // qui venait de sortir de la mémoire, l'appelant considérait le compte
    // comme un succès, et le bilan de « Tout recharger » comptait un échec
    // silencieux dans ses réussites. Une analyse ratée est un échec de
    // rechargement, au même titre qu'un téléchargement impossible.
    final reloaded = await ParsedPlaylistService.reloadFromDisk(
      account.id,
      account.label,
      newPath,
    );
    if (reloaded == null) {
      throw const HttpException('L\'analyse de la liste a échoué.');
    }
    debugPrint('✅ §reloadAll — « ${account.label} » rechargée '
        '(${reloaded.entries.length} entrées)');
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

  /// « Faut-il demander confirmation avant de recharger ? » — fonction PURE,
  /// partagée par le ↻ de l'accueil et les cartes de `AccountsPage` pour que
  /// les deux chemins posent la question au même moment.
  ///
  /// Pas de cache → pas de question (il n'y a rien à perdre).
  static bool shouldConfirm(Duration? age) =>
      age != null && age < confirmBelow;

  /// Âge lisible pour le dialogue : « 3h 12min », « 45min », « moins d'une
  /// minute ». Jamais de secondes — ce n'est pas un chronomètre.
  static String formatAge(Duration age) {
    final int h = age.inHours;
    final int m = age.inMinutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}min' : '${h}h';
    if (m > 0) return '${m}min';
    return 'moins d\'une minute';
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
