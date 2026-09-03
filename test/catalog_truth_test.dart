import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/xtream_api_service.dart';
import 'package:aetherStream/data/services/xtream_catalog_service.dart';

/// §catalogTruth — **« Vide » n'est pas « échec ».**
///
/// Le bug payé : `_listAction` rendait `const []` pour QUATRE situations
/// différentes — corps vide, `[]`, objet JSON, exception réseau. Un panel
/// limité à une connexion répondait `403 Too many connections` aux requêtes
/// surnuméraires (6 partaient en parallèle), l'échec devenait `[]`, et
/// `downloadCatalog` écrasait le catalogue complet précédent par un catalogue
/// amputé. Les deux fonctions testées ici sont **pures** : c'est là que vit la
/// décision, donc c'est là qu'on la verrouille.
void main() {
  group('classifyListBody — sept corps, deux verdicts', () {
    test('une liste non vide est un succès', () {
      final r = classifyListBody([
        {'stream_id': 1, 'name': 'TF1'},
        {'stream_id': 2, 'name': 'M6'},
      ], 200);
      expect(r.items, hasLength(2));
      expect(r.error, isNull);
      expect(r.kind, isNull);
    });

    test('[] est un SUCCÈS VIDE — le panel n\'a vraiment pas de films', () {
      final r = classifyListBody(const [], 200);
      expect(r.items, isNotNull);
      expect(r.items, isEmpty);
      expect(r.error, isNull);
    });

    test('un corps vide est un ÉCHEC (un panel sain répond au moins `[]`)', () {
      final r = classifyListBody(null, 200);
      expect(r.items, isNull);
      expect(r.error, isNotNull);
      expect(r.kind, LoadFailureKind.network);
    });

    test('{} est un échec, pas un catalogue vide', () {
      final r = classifyListBody(const <String, dynamic>{}, 200);
      expect(r.items, isNull);
      expect(r.error, isNotNull);
    });

    test('{"user_info": …} est un échec (le panel répond son bloc d\'auth)',
        () {
      final r = classifyListBody(const {
        'user_info': {'auth': 0, 'status': 'Expired'}
      }, 200);
      expect(r.items, isNull);
      expect(r.error, contains('authentification'));
    });

    test('un 4xx est un échec et porte son statut', () {
      final r = classifyListBody('Forbidden', 403);
      expect(r.items, isNull);
      expect(r.status, 403);
      expect(r.error, contains('403'));
    });

    test('un 403 « too many connections » est classé SATURÉ', () {
      final r =
          classifyListBody('Error: too many connections for this user', 403);
      expect(r.items, isNull);
      expect(r.kind, LoadFailureKind.busy,
          reason: 'c\'est le motif qu\'on veut voir sur la carte du compte');
      expect(labelForFailure(r.kind!), 'PANEL SATURÉ');
    });

    test('un 429 est saturé même sans texte explicite', () {
      expect(classifyListBody(null, 429).kind, LoadFailureKind.busy);
    });

    test('un 5xx / un timeout (statut absent) restent des échecs', () {
      expect(classifyListBody('<html>500</html>', 500).items, isNull);
      final t = classifyListBody(null, null);
      expect(t.items, isNull);
      expect(t.kind, LoadFailureKind.network);
    });

    test('du texte non-JSON est un échec, pas une liste vide', () {
      final r = classifyListBody('<html><body>Access denied</body></html>', 200);
      expect(r.items, isNull);
      expect(r.error, contains('illisible'));
    });

    test('une liste hétérogène ne garde que les objets', () {
      final r = classifyListBody([
        {'name': 'ok'},
        'bruit',
        42,
      ], 200);
      expect(r.items, hasLength(1));
    });
  });

  group('CatalogAcceptance.shouldWrite — écraser, ou garder l\'ancien', () {
    const plein = PlaylistCounts(films: 12000, series: 3000, tv: 900);

    test('3 sections ok et non vides → on écrit', () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 900,
        nVod: 12000,
        nSeries: 3000,
        previous: plein,
      );
      expect(v.write, isTrue);
      expect(v.failure, isNull);
    });

    test('une section en échec → REFUS, l\'ancien catalogue survit', () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: false,
        seriesOk: true,
        nLive: 900,
        nVod: 0,
        nSeries: 3000,
        previous: plein,
      );
      expect(v.write, isFalse);
      expect(v.failure, LoadFailureKind.amputated);
      expect(v.detail, contains('films'));
    });

    test('3 sections ok mais toutes vides → refus (catalogue sans intérêt)',
        () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 0,
        nVod: 0,
        nSeries: 0,
        previous: null,
      );
      expect(v.write, isFalse);
      expect(v.failure, LoadFailureKind.noSource);
    });

    test('⚠️ vod OK mais VIDE alors qu\'on avait 12 000 films → REFUS', () {
      // Le cas qui a coûté la liste de l'utilisateur : un panel saturé sait
      // répondre `200 []`. Les 6 actions « réussissent », et pourtant le
      // catalogue est faux.
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 900,
        nVod: 0,
        nSeries: 3000,
        previous: plein,
      );
      expect(v.write, isFalse);
      expect(v.failure, LoadFailureKind.amputated);
      expect(v.detail, contains('12000 → 0'));
    });

    test('vod vide mais AUCUN précédent → on écrit (rien à protéger)', () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 900,
        nVod: 0,
        nSeries: 0,
        previous: null,
      );
      expect(v.write, isTrue);
    });

    test('panel live-seul légitime (previous.films == 0) → on écrit', () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 1200,
        nVod: 0,
        nSeries: 0,
        previous: const PlaylistCounts(films: 0, series: 0, tv: 900),
      );
      expect(v.write, isTrue,
          reason: 'un abonnement TV seule ne doit pas être bloqué à vie');
    });

    test('une chute massive SANS passage à zéro reste acceptée', () {
      // ⚠️ Les compteurs `previous` sont POST-filtrage : comparer des
      // pourcentages entre deux mesures qui ne comptent pas la même chose
      // produirait des refus permanents. On ne teste QUE le zéro.
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 900,
        nVod: 1,
        nSeries: 3000,
        previous: plein,
      );
      expect(v.write, isTrue);
    });

    test('chaînes et séries vidées à la fois : le motif les nomme toutes', () {
      final v = CatalogAcceptance.shouldWrite(
        liveOk: true,
        vodOk: true,
        seriesOk: true,
        nLive: 0,
        nVod: 12000,
        nSeries: 0,
        previous: plein,
      );
      expect(v.write, isFalse);
      expect(v.detail, contains('chaînes'));
      expect(v.detail, contains('séries'));
    });
  });
}
