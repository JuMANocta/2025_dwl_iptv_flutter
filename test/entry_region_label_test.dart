// §legLang + §regionGaps (2026-09-05) — Le filtre « Langues / régions » n'avait
// AUCUN test, alors qu'il décide de ce qui est écrit sur le disque et de ce qui
// s'affiche. Trois défauts mesurés le 2026-09-05, tous couverts ici :
//
//  1. `|4K-LEG.|` et `|VO.LEG.|` échappaient au filtre — le code lu était
//     « 4K » et « VO.LEG. » parce que le découpage ignorait le point.
//  2. « LEG » (Legendado, portugais sous-titré — 3 215 entrées mesurées)
//     n'était pas une LANGUE : aucune pastille, indiscernable d'une VO.
//  3. Sept régions reléguées sous les genres n'étaient PAS masquables.
//
// ⚠️ Toutes les formes de préfixe ci-dessous sont RÉELLES (relevées dans
// `lib/iptv_exemple/PLATINIUM_vod_cache.json`), avec leur volume.

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§legLang — les six formes réelles du marqueur Legendado', () {
    // forme réelle → volume mesuré sur la liste
    const forms = <String, int>{
      '|LEG.| Toy Story 5 (2026)': 1801,
      '|VO-LEG.| Enola Holmes 2 (2022)': 1356,
      '|VO-LEG| Smile (2022)': 51,
      '|LEG| Some Film (2021)': 3,
      '|VO.LEG.| Test Movie (2022)': 2,
      '|4K-LEG.| Mission Impossible: Ajuste de Contas (Parte 1) (2023)': 1,
    };

    test('toutes sont détectées comme Legendado', () {
      forms.forEach((raw, volume) {
        expect(entryRegionLabels(raw), contains(kLegRegionLabel),
            reason: '$raw ($volume entrées réelles)');
      });
    });

    test('toutes restent masquables par « VO (non-FR) » (comportement gardé)', () {
      // Avant §legLang, une seule case couvrait ces titres. Masquer la VO doit
      // continuer de les masquer, sinon on ferait RÉAPPARAÎTRE du contenu que
      // l'utilisateur avait choisi de cacher.
      for (final raw in forms.keys) {
        expect(entryRegionLabels(raw), contains(kVoRegionLabel), reason: raw);
      }
    });

    test('toutes portent la LANGUE « LEG »', () {
      for (final raw in forms.keys) {
        expect(TitleMetadata.parse(raw).languages, contains('LEG'),
            reason: raw);
      }
    });

    test('aucune ne laisse de marqueur parasite « -LEG »', () {
      // ⚠️ LE défaut visible par l'utilisateur : sur `|4K-LEG.|`, le retrait du
      // bruit de qualité (« 4K ») laissait le tiret de TÊTE → la vignette
      // portait DEUX pastilles, « LEG » et « -LEG », pour un seul marqueur.
      for (final raw in forms.keys) {
        final tag = TitleMetadata.parse(raw).providerTag;
        expect(tag, isNot(anyOf(contains('LEG'), startsWith('-'))),
            reason: '$raw → tag=$tag');
      }
    });

    test('les deux copies de Mission : Impossible donnent UNE seule pastille', () {
      const a = '|LEG.| Mission Impossible: Ajuste de Contas (Parte 1) (2023)';
      const b = '|4K-LEG.| Mission Impossible: Ajuste de Contas (Parte 1) (2023)';
      final ma = TitleMetadata.parse(a);
      final mb = TitleMetadata.parse(b);
      // Même clé → une seule vignette…
      expect(ma.groupKey, mb.groupKey);
      // …et un seul et même jeu de marqueurs (c'est ce qui doublait).
      expect({ma.providerTag, mb.providerTag}, {null});
      expect(mb.quality, '4K'); // la qualité, elle, reste lue
    });

    test('⚠️ LEGO n\'est pas du portugais sous-titré', () {
      // Le contre-exemple qui impose les frontières de mot.
      expect(TitleMetadata.parse('LEGO Marvel Super Heroes (2014)').languages,
          isNot(contains('LEG')));
      expect(entryRegionLabels('LEGO Marvel Super Heroes (2014)'), isEmpty);
    });

    test('la catégorie lusophone porte le même libellé que le titre', () {
      // Le fournisseur nomme aussi des CATÉGORIES « VOD-LEGENDADA ».
      expect(contentCategoryLabel('VOD-LEGENDADA'), kLegRegionLabel);
      expect(contentCategoryLabel('ANIMACAO LEGENDADA'), kLegRegionLabel);
    });
  });

  group('§langFilter — ce qui ne doit JAMAIS être masqué', () {
    test('français, québécois, VOSTFR et sans préfixe', () {
      for (final raw in const [
        '|FR| TF1',
        '|FR-4K DV| Dune (2021)',
        '|QC| Un film québécois',
        '|VO|STFR| The Batman (2022)',
        '|VOSTFR| Oppenheimer (2023)',
        'Un film sans préfixe (2020)',
      ]) {
        expect(entryRegionLabels(raw), isEmpty, reason: raw);
      }
    });

    test('un code inconnu est gardé plutôt que masqué au hasard', () {
      expect(entryRegionLabels('|ZZ| Film inconnu'), isEmpty);
    });
  });

  group('§langFilter — les régions par code', () {
    test('le premier jeton du préfixe donne la région', () {
      expect(entryRegionLabels('|IT| Film italien'), {'Italie'});
      expect(entryRegionLabels('|IT-4K| Film italien 4K'), {'Italie'});
      expect(entryRegionLabels('|AR| فيلم'), {'Arabe'});
      expect(entryRegionLabels('|VO| Film en VO'), {kVoRegionLabel});
    });
  });

  group('§regionGaps — reléguer sans pouvoir masquer était un piège', () {
    test('toute région reléguée est masquable', () {
      // Sept manquaient : Bosnie, Canada, Coréen, Ex-Yougoslavie, Ramadan,
      // Rép. Dominicaine, Suisse. Elles occupaient le bas de l'accueil sans
      // que rien ne permette de les enlever.
      final missing = kForeignRegionLabels
          .where((r) => !kHideableRegionLabels.contains(r))
          .toList();
      expect(missing, isEmpty,
          reason: 'reléguées mais non masquables : $missing');
    });

    test('la liste masquable n\'a pas de doublon', () {
      expect(kHideableRegionLabels.toSet().length,
          kHideableRegionLabels.length);
    });
  });

  group('§legLang — le prédicat partagé du filtre', () {
    test('rien de masqué : court-circuit', () {
      expect(
        isRegionHidden(
            name: '|IT| Film', groupTitle: 'CINEMA', hidden: const {}),
        isFalse,
      );
    });

    test('voie TITRE', () {
      expect(
        isRegionHidden(name: '|IT| Film', hidden: const {'Italie'}),
        isTrue,
      );
    });

    test('voie CATÉGORIE — celle que le téléchargement oubliait', () {
      // ⚠️ Le filtre au téléchargement tournait AVANT la résolution des noms
      // de catégories : cette voie n'était jamais appliquée sur disque.
      expect(
        isRegionHidden(
          name: 'Un film sans préfixe',
          groupTitle: 'FILMS ITALIENS',
          hidden: const {'Italie'},
        ),
        isTrue,
      );
    });

    test('masquer Legendado n\'emporte pas tout le reste', () {
      const leg = '|LEG.| Toy Story 5 (2026)';
      const vo = '|VO| Un film en VO (2020)';
      expect(isRegionHidden(name: leg, hidden: const {kLegRegionLabel}), isTrue);
      // Une VO simple n'est PAS du legendado.
      expect(isRegionHidden(name: vo, hidden: const {kLegRegionLabel}), isFalse);
      // …mais masquer la VO emporte bien les deux (historique).
      expect(isRegionHidden(name: vo, hidden: const {kVoRegionLabel}), isTrue);
      expect(isRegionHidden(name: leg, hidden: const {kVoRegionLabel}), isTrue);
    });
  });
}
