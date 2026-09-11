import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/download_retry_policy.dart';

/// §dlNetRetry (2026-09-08) — « pendant un téléchargement si le réseau est out
/// il faut check et relancer ».
///
/// Toute erreur de flux basculait la tâche en `failed`, définitivement, alors
/// que la file ne regarde que les `queued` : perdre le Wi-Fi une minute
/// condamnait un transfert déjà à 90 %. Ces tests tiennent la frontière — ce
/// qui se reprend, et ce qui ne doit SURTOUT pas boucler.
void main() {
  final req = RequestOptions(path: '/film.mkv');

  group('classifyDownloadFailure — le tuyau ou la source ?', () {
    test('une annulation n\'est ni l\'un ni l\'autre', () {
      // ⚠️ Une RELANCE passe techniquement par là (§dlLoop) : la confondre
      // avec un échec réseau ferait repartir la tâche deux fois.
      expect(
        classifyDownloadFailure(
            DioException(requestOptions: req, type: DioExceptionType.cancel)),
        DownloadFailureKind.canceled,
      );
    });

    test('les délais dépassés et la connexion perdue sont du RÉSEAU', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(
          classifyDownloadFailure(DioException(requestOptions: req, type: t)),
          DownloadFailureKind.network,
          reason: '$t',
        );
      }
    });

    test('un 404 est un refus de la SOURCE, pas une panne de réseau', () {
      expect(
        classifyDownloadFailure(DioException(
          requestOptions: req,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: req, statusCode: 404),
        )),
        DownloadFailureKind.source,
      );
    });

    test('une SocketException nue est du RÉSEAU', () {
      expect(
        classifyDownloadFailure(const SocketException('reset')),
        DownloadFailureKind.network,
      );
    });

    test('🔴 une HttpException NATIVE anglaise est du réseau (§userErrorGaps)',
        () {
      // Le piège trouvé sur S25 réel : `dart:io` lance une `HttpException`
      // pour un simple accident de socket. Se fier à la CLASSE la classerait
      // en refus de source et condamnerait le transfert.
      expect(
        classifyDownloadFailure(
            const HttpException('Connection reset by peer')),
        DownloadFailureKind.network,
      );
    });

    test('🔴 un disque plein n\'est PAS du réseau', () {
      // `FileSystemException` hérite d'`IOException` comme `SocketException` :
      // sans traitement explicite, elle passerait pour une coupure et l'app
      // réessaierait indéfiniment d'écrire sur un disque qui reste plein.
      expect(
        classifyDownloadFailure(
            const FileSystemException('No space left on device')),
        DownloadFailureKind.source,
      );
    });

    test('une erreur Dio « unknown » est jugée sur sa CAUSE', () {
      expect(
        classifyDownloadFailure(DioException(
          requestOptions: req,
          type: DioExceptionType.unknown,
          error: const SocketException('Failed host lookup'),
        )),
        DownloadFailureKind.network,
      );
      expect(
        classifyDownloadFailure(DioException(
          requestOptions: req,
          type: DioExceptionType.unknown,
          error: 'Invalid argument(s)',
        )),
        DownloadFailureKind.source,
      );
    });

    test('un objet quelconque, sans indice, reste un échec de SOURCE', () {
      // Le repli prudent : on ne relance QUE ce qu'on a reconnu.
      expect(classifyDownloadFailure(Exception('boom')),
          DownloadFailureKind.source);
    });
  });

  group('shouldRequeueAfterFailure — ce qui repart, et jusqu\'à quand', () {
    test('une coupure réseau repart en file', () {
      expect(
        shouldRequeueAfterFailure(
            kind: DownloadFailureKind.network, requeues: 0),
        isTrue,
      );
    });

    test('un refus de la source ne repart JAMAIS', () {
      expect(
        shouldRequeueAfterFailure(
            kind: DownloadFailureKind.source, requeues: 0),
        isFalse,
      );
    });

    test('une annulation ne repart pas non plus', () {
      expect(
        shouldRequeueAfterFailure(
            kind: DownloadFailureKind.canceled, requeues: 0),
        isFalse,
      );
    });

    test('🔴 le plafond ferme la boucle', () {
      // Une source qui coupe la connexion à chaque tentative RESSEMBLE à une
      // panne réseau vue de l'app : sans plafond, elle serait martelée toute
      // la nuit.
      expect(
        shouldRequeueAfterFailure(
            kind: DownloadFailureKind.network,
            requeues: kMaxNetworkRequeues - 1),
        isTrue,
      );
      expect(
        shouldRequeueAfterFailure(
            kind: DownloadFailureKind.network, requeues: kMaxNetworkRequeues),
        isFalse,
        reason: 'au-delà du plafond, la tâche doit tomber en échec',
      );
    });
  });
}
