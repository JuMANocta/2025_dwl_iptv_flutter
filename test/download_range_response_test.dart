import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/download_range_policy.dart';

/// §dlRangeCheck (revue 2026-09-11, D3A-01) — La réponse du GET de
/// téléchargement est jugée AVANT d'écrire un octet.
///
/// Avant : un 403 « Too many connections » était ajouté au partiel puis la
/// tâche finissait « Terminé » ; un serveur qui ignore `Range` dupliquait le
/// film derrière les octets déjà reçus.
void main() {
  group('rangeResponseVerdict', () {
    test('🔴 un refus (403/404/401) ne s\'écrit JAMAIS dans le partiel', () {
      for (final code in [401, 403, 404, 410, 451]) {
        expect(
          rangeResponseVerdict(statusCode: code, resumedBytes: 2000000000),
          RangeVerdict.reject,
          reason: 'HTTP $code',
        );
        expect(
          rangeResponseVerdict(statusCode: code, resumedBytes: 0),
          RangeVerdict.reject,
          reason: 'HTTP $code sur un nouveau téléchargement',
        );
      }
    });

    test('redirection non suivie ou statut absent : refus', () {
      expect(rangeResponseVerdict(statusCode: 302, resumedBytes: 0),
          RangeVerdict.reject);
      expect(rangeResponseVerdict(statusCode: null, resumedBytes: 0),
          RangeVerdict.reject);
    });

    test('206 aligné sur l\'offset : on ajoute', () {
      expect(
        rangeResponseVerdict(
            statusCode: 206, resumedBytes: 1000, contentRangeStart: 1000),
        RangeVerdict.append,
      );
    });

    test('206 sans Content-Range lisible : on fait confiance au serveur', () {
      expect(rangeResponseVerdict(statusCode: 206, resumedBytes: 1000),
          RangeVerdict.append);
    });

    test('🔴 206 décalé : refus (ni ajout, ni réécriture depuis 0)', () {
      expect(
        rangeResponseVerdict(
            statusCode: 206, resumedBytes: 1000, contentRangeStart: 0),
        RangeVerdict.reject,
      );
      expect(
        rangeResponseVerdict(
            statusCode: 206, resumedBytes: 1000, contentRangeStart: 4096),
        RangeVerdict.reject,
      );
    });

    test('🔴 200 sur une reprise : le serveur ignore Range → repartir de 0', () {
      expect(rangeResponseVerdict(statusCode: 200, resumedBytes: 1000),
          RangeVerdict.restartFromZero);
    });

    test('200 sur un partiel vide : cas nominal', () {
      expect(rangeResponseVerdict(statusCode: 200, resumedBytes: 0),
          RangeVerdict.append);
    });

    test('416 sur un partiel non vide : déjà complet', () {
      expect(rangeResponseVerdict(statusCode: 416, resumedBytes: 5000),
          RangeVerdict.alreadyComplete);
    });

    test('416 sur un partiel VIDE : refus (rien à finaliser)', () {
      expect(rangeResponseVerdict(statusCode: 416, resumedBytes: 0),
          RangeVerdict.reject);
    });
  });

  group('parseContentRangeStart', () {
    test('forme standard', () {
      expect(parseContentRangeStart('bytes 100-999/1000'), 100);
      expect(parseContentRangeStart('bytes 0-99/*'), 0);
    });

    test('absent ou illisible → null', () {
      expect(parseContentRangeStart(null), isNull);
      expect(parseContentRangeStart('bytes */1000'), isNull);
      expect(parseContentRangeStart('n\'importe quoi'), isNull);
    });
  });

  group('isDownloadableStatus', () {
    test('2xx seulement', () {
      expect(isDownloadableStatus(200), isTrue);
      expect(isDownloadableStatus(206), isTrue);
      expect(isDownloadableStatus(301), isFalse);
      expect(isDownloadableStatus(403), isFalse);
      expect(isDownloadableStatus(416), isFalse);
      expect(isDownloadableStatus(null), isFalse);
    });
  });
}
