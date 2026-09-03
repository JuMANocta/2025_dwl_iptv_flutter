import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/playlist_fleet_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// §fleetLoad — L'invariant se teste ici, sans appareil ni réseau : toute
/// liste finit chargée, ou porte un échec motivé.
FleetStep step({
  bool inMemory = false,
  int entriesInMemory = 0,
  bool hasParsedCache = false,
  bool hasSourceFile = false,
  bool sourceIsStale = false,
  bool allowNetwork = true,
  bool allowReparse = true,
}) =>
    FleetPolicy.nextStep(
      inMemory: inMemory,
      entriesInMemory: entriesInMemory,
      hasParsedCache: hasParsedCache,
      hasSourceFile: hasSourceFile,
      sourceIsStale: sourceIsStale,
      allowNetwork: allowNetwork,
      allowReparse: allowReparse,
    );

void main() {
  group('FleetPolicy — l\'escalade', () {
    test('en mémoire avec des entrées et une source fraîche : rien à faire', () {
      expect(step(inMemory: true, entriesInMemory: 12000), FleetStep.none);
    });

    test('en mémoire mais à ZÉRO entrée : ce n\'est pas un succès', () {
      // Le symptôme d'un catalogue amputé. L'ancien code le comptait chargé.
      expect(step(inMemory: true, entriesInMemory: 0, hasSourceFile: true),
          isNot(FleetStep.none));
    });

    test('cache analysé présent et source fraîche : lecture disque', () {
      expect(step(hasParsedCache: true, hasSourceFile: true),
          FleetStep.loadCache);
    });

    test('pas de cache mais un catalogue brut : ré-analyse (le repli manquant)',
        () {
      expect(step(hasSourceFile: true), FleetStep.reparse);
    });

    test('ré-analyse interdite : on ne ré-analyse pas, on télécharge', () {
      expect(step(hasSourceFile: true, allowReparse: false),
          FleetStep.download);
    });

    test('rien sur le disque : téléchargement', () {
      expect(step(), FleetStep.download);
    });

    test('rien sur le disque et réseau interdit : échec motivé', () {
      expect(step(allowNetwork: false), FleetStep.fail);
    });

    test('source périmée avec réseau : on rafraîchit', () {
      expect(
        step(hasParsedCache: true, hasSourceFile: true, sourceIsStale: true),
        FleetStep.download,
      );
    });

    test('source périmée SANS réseau : périmé vaut mieux que rien', () {
      expect(
        step(
          hasParsedCache: true,
          hasSourceFile: true,
          sourceIsStale: true,
          allowNetwork: false,
        ),
        FleetStep.loadCache,
      );
    });

    test('en mémoire mais source périmée : on rafraîchit quand même', () {
      expect(
        step(inMemory: true, entriesInMemory: 500, sourceIsStale: true),
        FleetStep.download,
      );
    });

    test('en mémoire, source périmée, réseau interdit : on garde', () {
      expect(
        step(
          inMemory: true,
          entriesInMemory: 500,
          sourceIsStale: true,
          allowNetwork: false,
        ),
        FleetStep.none,
      );
    });

    test('aucune combinaison ne rend null : la décision est totale', () {
      for (final a in [true, false]) {
        for (final b in [true, false]) {
          for (final c in [true, false]) {
            for (final d in [true, false]) {
              for (final e in [true, false]) {
                expect(
                  step(
                    inMemory: a,
                    entriesInMemory: a ? 10 : 0,
                    hasParsedCache: b,
                    hasSourceFile: c,
                    sourceIsStale: d,
                    allowNetwork: e,
                  ),
                  isA<FleetStep>(),
                );
              }
            }
          }
        }
      }
    });
  });

  group('FleetReport — le bilan se lit en une phrase', () {
    test('aucun compte', () {
      expect(const FleetReport(total: 0).summary, contains('aucun compte'));
    });

    test('tout chargé', () {
      const r = FleetReport(total: 3, loaded: 3, fromCache: 2, reparsed: 1);
      expect(r.allLoaded, isTrue);
      expect(r.summary, contains('3/3'));
      expect(r.summary, contains('ré-analysée'));
    });

    test('échecs et reports sont nommés', () {
      final r = FleetReport(
        total: 3,
        loaded: 1,
        failed: {
          'a': LoadFailure(LoadFailureKind.busy, at: DateTime(2026, 9, 3))
        },
        deferred: const ['Premium'],
      );
      expect(r.allLoaded, isFalse);
      expect(r.summary, contains('1 en échec'));
      expect(r.summary, contains('1 reportée'));
    });
  });

  group('LoadFailure — chaque cause a un libellé distinct', () {
    test('aucune valeur ne retombe sur « NON CHARGÉ » par défaut', () {
      final labels = <String>{};
      for (final k in LoadFailureKind.values) {
        final l = labelForFailure(k);
        expect(l, isNotEmpty);
        labels.add(l);
      }
      // Seul `never` a le droit de s'appeler « NON CHARGÉ ».
      expect(labels.where((l) => l == 'NON CHARGÉ').length, 1);
      expect(labels.length, LoadFailureKind.values.length);
    });

    test('les trois situations bénignes sont reconnues comme telles', () {
      final at = DateTime(2026, 9, 3);
      expect(LoadFailure(LoadFailureKind.unloadedIdle, at: at).isBenign, isTrue);
      expect(LoadFailure(LoadFailureKind.deferred, at: at).isBenign, isTrue);
      expect(LoadFailure(LoadFailureKind.never, at: at).isBenign, isTrue);
      expect(LoadFailure(LoadFailureKind.busy, at: at).isBenign, isFalse);
      expect(LoadFailure(LoadFailureKind.amputated, at: at).isBenign, isFalse);
    });

    test('le détail est ajouté à la phrase quand il existe', () {
      final f = LoadFailure(LoadFailureKind.busy,
          detail: 'get_vod_streams : 403', at: DateTime(2026, 9, 3));
      expect(describeFailure(f), contains('403'));
      expect(describeFailure(f), contains('connexions'));
    });
  });
}
