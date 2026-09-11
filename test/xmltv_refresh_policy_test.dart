import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';

/// Revue 2026-09-11 — Le guide des chaînes (XMLTV) :
///   - D1B-04 : « Rafraîchir le guide » relisait le fichier de moins de 24 h
///     sans rien télécharger, et annonçait « Guide mis à jour » ;
///   - D4B-04 : un téléchargement raté était retenté à CHAQUE accesseur (trois
///     par ouverture de la feuille d'une chaîne), d'où des secondes d'attente.
void main() {
  group('readCacheFirst (D1B-04)', () {
    test('fichier récent, sans forcer → on lit le cache', () {
      expect(
          XmltvService.readCacheFirst(
              age: const Duration(hours: 2), force: false),
          isTrue);
    });

    test('⚠️ fichier récent MAIS rafraîchissement demandé → réseau', () {
      expect(
          XmltvService.readCacheFirst(
              age: const Duration(minutes: 5), force: true),
          isFalse);
    });

    test('fichier de plus de 24 h → réseau', () {
      expect(
          XmltvService.readCacheFirst(
              age: const Duration(hours: 25), force: false),
          isFalse);
    });

    test('pas de fichier → réseau', () {
      expect(XmltvService.readCacheFirst(age: null, force: false), isFalse);
    });
  });

  group('failureStillFresh (D4B-04)', () {
    final DateTime now = DateTime(2026, 9, 11, 20);

    test('aucun échec → on peut tenter', () {
      expect(XmltvService.failureStillFresh(null, now), isFalse);
    });

    test('échec il y a 30 s → on ne retente pas (la feuille s\'ouvre net)', () {
      expect(
          XmltvService.failureStillFresh(
              now.subtract(const Duration(seconds: 30)), now),
          isTrue);
    });

    test('échec il y a 5 min → on retente', () {
      expect(
          XmltvService.failureStillFresh(
              now.subtract(const Duration(minutes: 5)), now),
          isFalse);
    });
  });
}
