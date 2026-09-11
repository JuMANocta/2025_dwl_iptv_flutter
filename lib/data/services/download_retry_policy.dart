/// §dlNetRetry — Distinguer « le tuyau a sauté » de « la source refuse ».
///
/// **Le défaut payé** (signalé le 2026-09-08 : « pendant un téléchargement si
/// le réseau est out il faut check et relancer ») : toute erreur de flux
/// basculait la tâche en `failed`, définitivement. Or la file ne regarde que
/// les tâches `queued` (`_pumpOnce` sort tout de suite s'il n'y en a aucune),
/// et `NetworkStatusService` sait pourtant dire à la seconde près quand le
/// réseau revient. Perdre le Wi-Fi une minute suffisait donc à condamner un
/// transfert de plusieurs gigaoctets déjà à 90 %.
///
/// ⚠️ **Tout ne se reprend pas.** Un 404, un 403 ou un disque plein ne
/// guériront pas d'eux-mêmes : les remettre en file ferait tourner l'app à
/// vide toute la nuit. D'où cette classification, extraite du service pour
/// être testable — le reste de `DownloadManagerService` traîne un Dio, des
/// fichiers et un singleton.
library;

import 'dart:io';

import 'package:dio/dio.dart';

/// Ce qui a interrompu un transfert.
enum DownloadFailureKind {
  /// Le réseau a lâché (coupure, DNS, socket fermée, délai dépassé). La source
  /// n'a rien refusé : elle n'a simplement pas pu être jointe, ou plus.
  network,

  /// La source a répondu, et sa réponse est un refus (404, 403, 401…), ou
  /// l'échec vient de l'appareil (disque plein, chemin invalide). Réessayer
  /// n'y changera rien tant que rien d'autre ne bouge.
  source,

  /// Annulation demandée par l'app ou l'utilisateur — ni un échec, ni à
  /// reprendre. ⚠️ Une RELANCE passe techniquement par là (§dlLoop).
  canceled,
}

/// Nombre maximal de remises en file pour une même tâche, sur une même session.
///
/// ⚠️ Sans plafond, une source qui coupe la connexion à chaque tentative — ce
/// qui ressemble à une panne réseau vu de l'app — serait martelée sans fin.
/// Trois essais laissent passer une coupure Wi-Fi ou un changement d'antenne
/// sans transformer une source morte en boucle.
const int kMaxNetworkRequeues = 3;

/// Classe l'erreur qui a interrompu un transfert.
///
/// ⚠️ **Ne pas se fier à la seule CLASSE de l'exception** : `dart:io` et Dio
/// lancent une `HttpException` **native** (anglaise, « Connection reset by
/// peer ») pour un simple accident de socket — c'est le piège §userErrorGaps,
/// trouvé sur un S25 réel et invisible sur émulateur.
DownloadFailureKind classifyDownloadFailure(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return DownloadFailureKind.canceled;
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return DownloadFailureKind.network;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
        // Le serveur a RÉPONDU : son refus ne guérira pas tout seul.
        return DownloadFailureKind.source;
      case DioExceptionType.transformTimeout:
        // Le traitement LOCAL de la réponse a dépassé son délai : le réseau
        // n'y est pour rien, relancer ne changerait rien.
        return DownloadFailureKind.source;
      case DioExceptionType.unknown:
        return _fromCause(error.error ?? error.message ?? '');
    }
  }
  return _fromCause(error);
}

DownloadFailureKind _fromCause(Object cause) {
  if (cause is SocketException) return DownloadFailureKind.network;
  if (cause is HandshakeException) return DownloadFailureKind.network;
  // ⚠️ `FileSystemException` d'abord : elle hérite de `IOException` comme
  // `SocketException`, mais un disque plein n'est PAS une panne de réseau.
  if (cause is FileSystemException) return DownloadFailureKind.source;
  final String text = cause.toString().toLowerCase();
  const List<String> networkMarkers = [
    'connection reset',
    'connection closed',
    'connection refused',
    'connection aborted',
    'connection terminated',
    'software caused connection abort',
    'broken pipe',
    'network is unreachable',
    'no route to host',
    'failed host lookup',
    'timed out',
    'timeout',
  ];
  for (final m in networkMarkers) {
    if (text.contains(m)) return DownloadFailureKind.network;
  }
  return DownloadFailureKind.source;
}

/// `true` si la tâche doit repartir en FILE d'attente au lieu de tomber en
/// échec — la file la relancera d'elle-même dès que le réseau reviendra
/// (mécanique §dlWifi déjà en place, reprise `Range` déjà écrite).
///
/// [requeues] = nombre de remises en file déjà accordées à CETTE tâche.
bool shouldRequeueAfterFailure({
  required DownloadFailureKind kind,
  required int requeues,
  int maxRequeues = kMaxNetworkRequeues,
}) {
  if (kind != DownloadFailureKind.network) return false;
  return requeues < maxRequeues;
}
