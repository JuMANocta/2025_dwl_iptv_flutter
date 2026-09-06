// §catFix (2026-09-05) — `contentCategoryLabel` n'avait AUCUN test alors qu'il
// décide du rangement de 320 000 entrées à l'accueil.
//
// ⚠️ **Tous les `group-title` de ce fichier sont RÉELS**, relevés dans
// `lib/iptv_exemple/playlist_racine_2025-12.m3u`. Un cas inventé ne prouve rien
// ici : le défaut corrigé (51 % des séries dans une seule rangée) venait
// justement d'une forme que personne n'avait regardée.

import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le suffixe que ce fournisseur colle à TOUS ses group-titles de séries.
/// C'est lui qui a fait tomber 52 991 séries dans « Paramount+ ».
const String _sources = ' ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ )';

void main() {
  group('§catFix — le genre se lit sur le segment principal', () {
    test('le suffixe de sources du fournisseur ne classe plus rien', () {
      // Les 18 group-titres séries réels, dans l'ordre décroissant de volume.
      const cases = <String, String>{
        'COMEDIE': 'Comédie',
        'DRAME': 'Drame',
        'ANIMATION - ENFANT': 'Animation',
        'AVENTURE | FANTASTIQUE': 'Aventure',
        'CRIME': 'Crime',
        'POLICIER': 'Policier',
        'SCIENCE FICTION': 'Sci-Fi',
        'THRILLER': 'Thriller',
        'MEDECINE': 'Médecine',
        'ACTION': 'Action',
        'ESPIONNAGE & POLITIQUE': 'Espionnage',
        'HORREUR | MYSTERE': 'Horreur',
        'SUPER-HEROS': 'Super-Héros',
        'MAFIA & GANG': 'Mafia',
        'DOCUMENTAIRE - BIOPIC': 'Documentaire',
        'ROMANCE': 'Romance',
        'RÉALITÉ': 'Téléréalité',
        'JURIDIQUE': 'Juridique',
        'CORÉENNE | KOREA SERIES': 'Coréen',
        'MEDIEVAL |MOYEN AGE': 'Médiéval',
        'WESTERN - HISTORIQUE': 'Western',
        'BRAQUAGE & ARNAQUE': 'Braquage',
        'TUEUR EN SERIE': 'Tueur en série',
        'PRISON': 'Prison',
        'MUSICAL': 'Musical',
      };
      cases.forEach((group, expected) {
        expect(contentCategoryLabel('$group$_sources'), expected,
            reason: 'group-title réel « $group$_sources »');
      });
    });

    test('un multi-genres est classé par son PREMIER segment', () {
      // ⚠️ Avant §catFix, l'ordre du CODE tranchait : ACTION était testé avant
      // POLICIER, donc ces 550 films partaient en « Action ».
      expect(contentCategoryLabel('POLICIER | ACTION | CRIME'), 'Policier');
      expect(contentCategoryLabel('THRILLER | DRAME | GUERRE'), 'Thriller');
      expect(contentCategoryLabel('SC FICTION | HORREUR'), 'Sci-Fi');
      expect(contentCategoryLabel('FANTASTIQUE | AVENTURE'), 'Fantastique');
      expect(contentCategoryLabel('DRAME | HISTOIRE'), 'Drame');
      expect(contentCategoryLabel('WESTERN | HISTORIQUE'), 'Western');
      expect(contentCategoryLabel('ANIMATION | FAMILIALE | ENFANTS'), 'Animation');
      expect(contentCategoryLabel('DOCUMENTAIRES | EMISSION TV'), 'Documentaire');
    });

    test('la partie utile après le pipe reste rattrapée', () {
      // Le segment principal est en arabe ; le repli sur la chaîne entière
      // doit encore fonctionner.
      expect(contentCategoryLabel('افلام عربية | FILMS ARABES'), 'Arabe');
      expect(contentCategoryLabel('مسلسلات تركية | SERIES TURQUES'), 'Turc');
    });
  });

  group('§catFix — plateformes et formats ne sont pas des genres', () {
    test('une plateforme seule reste une catégorie', () {
      expect(contentCategoryLabel('DISNEY +'), 'Disney+');
      expect(contentCategoryLabel('PARAMOUNT+'), 'Paramount+');
      expect(contentCategoryLabel('BrutX ORIGINAL'), 'BrutX');
    });

    test('une plateforme citée en passant ne classe rien', () {
      // Bouquet de chaînes Canal+ : c'est du sport, pas du Disney+.
      expect(
        contentCategoryLabel(
            "FR CANAL+ LIVE | DISNEY+ WOMEN'S CHAMPION'S LEAGUE (France)"),
        'Sport',
      );
    });

    test('les formats sont gardés, mais après les genres', () {
      // ⚠️ Ces rangées sont VOLONTAIREMENT conservées : les supprimer ne
      // libérait que 0,7 % des entrées et renvoyait 800 films vers un repli
      // littéral sans genre — pire que le défaut.
      expect(contentCategoryLabel('|VOD| 4K (HDR)'), '4K HDR');
      expect(contentCategoryLabel('4K HDR - MUTLI'), '4K HDR');
      expect(contentCategoryLabel('UHD IMAX'), 'IMAX');
      expect(contentCategoryLabel('3D (MULTI)'), '3D');
      // Un genre l'emporte sur le format.
      expect(contentCategoryLabel('ACTION 4K HDR'), 'Action');
    });
  });

  group('§catFix — les pièges de vocabulaire', () {
    test("l'apostrophe typographique ne fait plus rater le test", () {
      // ⚠️ `’` (U+2019) ≠ `'` (ASCII). 63 films tombaient en repli littéral.
      expect(contentCategoryLabel('FILMS DE FIN D’ANNÉE'), 'Fêtes');
      expect(contentCategoryLabel("FILMS DE FIN D'ANNÉE"), 'Fêtes');
    });

    test('« comédie musicale » n\'est plus du code mort', () {
      // Le test dédié vivait APRÈS `COMEDIE` : il ne pouvait jamais tomber.
      expect(contentCategoryLabel('COMEDIE MUSICAL'), 'Musical');
      expect(contentCategoryLabel('MUSICAL'), 'Musical');
    });

    test('Cultes et Classiques sont une seule rangée', () {
      expect(contentCategoryLabel("70'S | 80'S |OLD| CULTES"), 'Cultes');
      expect(contentCategoryLabel('CLASSIC'), 'Cultes');
      expect(contentCategoryLabel('LEGENDAIRES | ANCIENS FILMS'), 'Cultes');
    });

    test('le rayon jeunesse est reconnu dans les autres langues', () {
      for (final g in const [
        'KINDER DE', 'NINOS ES', 'BAMBINI', 'INFANTIL BR', 'VOD CRIANCAS',
        'KIDS UK', 'ENFANTS',
      ]) {
        expect(contentCategoryLabel(g), 'Jeunesse', reason: g);
      }
    });

    test('les actualités ont enfin un libellé', () {
      for (final g in const [
        'NEWS UK', 'NACHRICHTEN DE', 'NOTIZIE', 'NOTICIAS ES', 'ACTUALITÉS',
      ]) {
        expect(contentCategoryLabel(g), 'Actualités', reason: g);
      }
    });

    test('ENGLISH FILMS devient UK (donc masquable)', () {
      // Demande utilisateur : cette catégorie devait pouvoir se masquer dans
      // « Langues / régions ». `UK` y figure déjà.
      expect(contentCategoryLabel('ENGLISH FILMS'), 'UK');
      expect(contentCategoryLabel('ENGLISH MOVIES'), 'UK');
      expect(kHideableRegionLabels, contains('UK'));
    });

    test('FRANÇAIS a un libellé propre au lieu des majuscules', () {
      // 696 films tombaient en repli littéral « FRANÇAIS ».
      expect(contentCategoryLabel('FRANÇAIS'), 'Français');
      // ⚠️ Et il ne doit PAS être relégué en bas de l'accueil.
      expect(kForeignRegionLabels, isNot(contains('Français')));
    });

    test('le sport nommé par sa compétition est du sport', () {
      expect(
        contentCategoryLabel('LIGUE 1+ FRANCE | DAZN| MAGNUS TV | FANSEAT FRANCE'),
        'Sport',
      );
      expect(
        contentCategoryLabel('DAZN ITALIA SERIE A / SERIE B ( SOLO DIRETTO )'),
        'Sport',
      );
    });
  });

  group('§catFix — ce qui ne doit PAS changer', () {
    test('le préfixe de région garde la priorité absolue', () {
      expect(contentCategoryLabel('|IT| ITALIAN SERIES'), 'Italie');
      expect(contentCategoryLabel('|TR| YERLI DIZILER'), 'Turc');
      // `|FR|` n'est pas une région étrangère → rangé par genre.
      expect(contentCategoryLabel('|FR| SERIES COMEDIE'), 'Comédie');
    });

    test('un group-title inconnu reste repris tel quel, tronqué', () {
      expect(contentCategoryLabel('CANALSAT AF HD (AFRIQUE)'), 'CANALSAT AF HD');
      expect(contentCategoryLabel(''), isNull);
      expect(contentCategoryLabel(null), isNull);
    });

    test('les formulations « nouveauté » tombent toutes dans New', () {
      expect(contentCategoryLabel('FILMS RÉCEMMENT AJOUTÉS'), 'New');
      expect(contentCategoryLabel('RECEMMENT AJOUTÉES'), 'New');
    });
  });

  group('§catWords — les mots de type ne sont jamais un libellé', () {
    // ⚠️ Ces group-titles ont été RELEVÉS À L'ÉCRAN sur le téléviseur de
    // recette (2026-09-05, vrai catalogue) : le repli littéral recopie le
    // group-title tel quel, donc le nom de la rangée EST la forme du
    // fournisseur. Le nombre entre parenthèses est le volume mesuré.
    test('un group-title réduit à un mot de type rend null (→ « Autres »)', () {
      expect(contentCategoryLabel('FILMES'), isNull); // 3 299 films !
      expect(contentCategoryLabel('FILMS'), isNull); // 289
      expect(contentCategoryLabel('MOVIES'), isNull); // 137
      expect(contentCategoryLabel('SERIES'), isNull);
      expect(contentCategoryLabel('VOD'), isNull);
    });

    test('le genre caché derrière le mot de type est enfin lu', () {
      expect(contentCategoryLabel('FILMS ART-MARTIAUX'), 'Arts martiaux'); // 103
      expect(contentCategoryLabel('FILMS | ART-MARTIAUX'), 'Arts martiaux');
      expect(contentCategoryLabel('FILMS DE NOËL'), 'Fêtes'); // 472
      expect(contentCategoryLabel('FILMS ANCIENS'), 'Cultes'); // 2 023
      expect(contentCategoryLabel('FILMS FAMILY'), 'Jeunesse'); // 114
      expect(contentCategoryLabel('FILMS DUBBED AR'), 'Arabe'); // 122
      expect(contentCategoryLabel('FILMS 4K'), '4K'); // 4
      expect(contentCategoryLabel('NETFLIX FILMS'), 'Netflix'); // 73
    });

    test('les rangées en doublon d\'un même genre fusionnent', () {
      // Sci-Fi 164 + SCIENCE-FICTION 368 ; Arts martiaux 99 + FILMS
      // ART-MARTIAUX 103 ; Fêtes 15 + FILMS DE NOËL 472.
      expect(contentCategoryLabel('SCIENCE-FICTION'), 'Sci-Fi');
      expect(contentCategoryLabel('SCIENCE FICTION'), 'Sci-Fi');
      expect(contentCategoryLabel('ARTS MARTIAUX'), 'Arts martiaux');
      expect(contentCategoryLabel('FIN D\'ANNÉE'), 'Fêtes');
    });

    test('les régions écrites en majuscules deviennent des régions', () {
      expect(contentCategoryLabel('SÉRIES ASIATIQUES'), 'Asie'); // 734
      expect(contentCategoryLabel('FILMS ASIE'), 'Asie'); // 231
      expect(contentCategoryMatch('FILMS ASIE')!.source, CategorySource.region);
      // Reléguée ET masquable, comme toute région (garde-fou §regionGaps).
      expect(kForeignRegionLabels, contains('Asie'));
      expect(kHideableRegionLabels, contains('Asie'));
    });

    test('les autres rangées littérales relevées trouvent leur rayon', () {
      expect(contentCategoryLabel('V.O SOUS TITRÉS'), 'VOSTFR'); // 1 635
      expect(contentCategoryLabel('KARAOKE'), 'Karaoké'); // 350
      expect(contentCategoryLabel('THÉÂTRES'), 'Spectacle'); // 83
      expect(contentCategoryLabel('COMICS'), 'Super-Héros'); // 72
      expect(contentCategoryLabel('DC/DCEU'), 'Super-Héros'); // 1
      expect(contentCategoryLabel('TOP 100'), 'Sélection'); // 40
      // Un vrai reste littéral perd son mot de type et garde sa casse.
      expect(contentCategoryLabel('FILMS SAGA'), 'SAGA'); // 38
    });

    test('Dolby Vision est du HDR : une seule rangée', () {
      expect(contentCategoryLabel('4K DOLBY VISION'), '4K HDR'); // 604
      expect(contentCategoryLabel('100% DOLBY VISION'), '4K HDR'); // 4
      expect(contentCategoryLabel('4K HDR'), '4K HDR'); // 564
      expect(contentCategoryLabel('4K'), '4K'); // 9
      // ⚠️ « DOLBY DIGITAL » (un bouquet TV réel) n'est PAS du HDR.
      expect(contentCategoryLabel('FR TV CINEMA FHD ( DOLBY DIGITAL)'),
          'FR TV CINEMA FHD');
    });

    test('⚠️ les accents du fournisseur ne sont jamais exactement les nôtres', () {
      // Relevé DEUX fois sur le téléviseur : « THÉÂTRES » puis « THÉATRES »
      // (É précomposé, A sans circonflexe) restaient littéraux. Toute graphie
      // accentuée — précomposée, décomposée, partielle — doit converger.
      expect(contentCategoryLabel('THÉÂTRES'), 'Spectacle');
      expect(contentCategoryLabel('THÉATRES'), 'Spectacle');
      expect(contentCategoryLabel('THEATRES'), 'Spectacle');
      expect(contentCategoryLabel('THÉÂTRES'), 'Spectacle'); // NFD
      expect(contentCategoryLabel('ÉPOUVANTE'), 'Horreur');
      expect(contentCategoryLabel('Epouvante'), 'Horreur');
      expect(contentCategoryLabel('COMÉDIE'), 'Comédie');
      expect(contentCategoryLabel('COMÉDIE'), 'Comédie');
      expect(contentCategoryLabel('COUP DE CŒUR'), 'Coup de cœur'); // Œ → OE
      expect(contentCategoryLabel('ESPAÑA'), 'Espagne');
      // Trouvés par la revue : deux mots-clés n'existaient QU'en accentué,
      // donc ne pouvaient plus jamais décider après le repli.
      expect(contentCategoryLabel('SÉRIES CORÉENNES'), 'Coréen');
      expect(contentCategoryLabel('FILMES PORTUGUÊS'), 'Portugal');
    });

    test('le vocabulaire portugais est reconnu (formes plausibles)', () {
      // Le fournisseur du LEGENDADO écrit ses genres en portugais ; ces
      // group-titles sont la forme ATTENDUE derrière la rangée « FILMES »
      // (3 299 films), pas des relevés — le catalogue n'est pas dumpable.
      expect(contentCategoryLabel('FILMES | AÇÃO'), 'Action');
      expect(contentCategoryLabel('FILMES | ACAO'), 'Action');
      expect(contentCategoryLabel('FILMES | COMÉDIA'), 'Comédie');
      expect(contentCategoryLabel('FILMES | TERROR'), 'Horreur');
      expect(contentCategoryLabel('FILMES | AVENTURA'), 'Aventure');
      expect(contentCategoryLabel('FILMES | SUSPENSE'), 'Thriller');
      expect(contentCategoryLabel('FILMES | FAROESTE'), 'Western');
      expect(contentCategoryLabel('FILMES | GUERRA'), 'Guerre');
      expect(contentCategoryLabel('SERIES | POLICIAL'), 'Policier');
      expect(contentCategoryLabel('ANIMAÇÃO'), 'Animation');
    });

    test('⚠️ LEGENDADO prime sur le genre, comme toute région', () {
      // Avant que « ANIMAÇÃO » soit reconnu, ce group-title tombait dans
      // Legendado par défaut. Il doit y RESTER : sinon la case « Legendado »
      // ne masquerait plus ces séries.
      expect(contentCategoryLabel('ANIMACAO LEGENDADA'), kLegRegionLabel);
      expect(contentCategoryLabel('SERIES | ANIMACAO LEGENDADA'), kLegRegionLabel);
      expect(contentCategoryLabel('VOD-LEGENDADA'), kLegRegionLabel);
    });

    test('non-régression sur les formes réelles du dump', () {
      expect(contentCategoryLabel('LEGENDAIRES | ANCIENS FILMS'), 'Cultes'); // 201
      expect(contentCategoryLabel('أفلام عربية قديمة | ANCIENS FILMS ARABES'),
          'Arabe'); // 104
      expect(contentCategoryLabel('DAZN ITALIA SERIE A'), 'Sport');
      expect(contentCategoryLabel('COMEDIE$_sources'), 'Comédie');
    });

    test('la liste des régions masquables est triée (recette 2026-09-05)', () {
      // « Arménie » précédait « Albanie » à l'écran.
      // ⚠️ Ordre HUMAIN, pas ordre des points de code : `compareTo` mettrait
      // « Roumanie » avant « Rép. Dominicaine » (é > o). On replie l'accent.
      String key(String s) => s
          .toLowerCase()
          .replaceAll(RegExp('[éèêë]'), 'e')
          .replaceAll(RegExp('[àâä]'), 'a');
      final regions = kHideableRegionLabels
          .where((r) => r != kVoRegionLabel && r != kLegRegionLabel)
          .toList();
      final sorted = [...regions]..sort((a, b) => key(a).compareTo(key(b)));
      expect(regions, sorted);
      expect(kHideableRegionLabels.last, kLegRegionLabel);
    });
  });

  group('§catMeter — la provenance est correctement attribuée', () {
    test('chaque source est reconnue', () {
      expect(contentCategoryMatch('|IT| CINEMA')!.source, CategorySource.region);
      expect(contentCategoryMatch('COMEDIE')!.source, CategorySource.genre);
      expect(contentCategoryMatch('DISNEY +')!.source, CategorySource.platform);
      expect(contentCategoryMatch('|VOD| 4K (HDR)')!.source, CategorySource.format);
      expect(contentCategoryMatch('CANALSAT AF HD (AFRIQUE)')!.source,
          CategorySource.literal);
    });
  });
}
