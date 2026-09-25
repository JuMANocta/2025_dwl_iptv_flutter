// §imgRightSize (2026-09-25) — Les adresses TMDB demandées à la taille dont
// l'écran a besoin (`tmdbSizedUrl`), et l'adresse d'origine gardée en repli
// (`AetherImage.candidates`).
//
// Constat mesuré le 2026-09-22 : les listes pointent surtout vers TMDB en
// grand format (PremiumV2 : 16 104 en `w600_and_h900_bestv2`, 9 047 en
// `w1280`) pour des vignettes décodées à ~290 px. Échelle vérifiée le
// 2026-09-25 sur image.tmdb.org : w92…w1280 rendent 200 (affiche ET fond),
// `w999` rend 400.
import 'package:aetherStream/widgets/aether_image.dart';
import 'package:flutter_test/flutter_test.dart';

const String _poster = 'https://image.tmdb.org/t/p/w600_and_h900_bestv2/wf0Gi6Mf9Yl00uSM1TD4zEMYkgV.jpg';
const String _file = '/wf0Gi6Mf9Yl00uSM1TD4zEMYkgV.jpg';
String _w(String size) => 'https://image.tmdb.org/t/p/$size$_file';

void main() {
  group('tmdbSizedUrl — descendre à la taille affichée, jamais sous 90 %', () {
    test('affiche 600×900 pour une vignette décodée à 290 px → w342', () {
      expect(tmdbSizedUrl(_poster, 290), _w('w342'));
    });

    test('w1280 et original descendent aussi', () {
      expect(tmdbSizedUrl(_w('w1280'), 290), _w('w342'));
      expect(tmdbSizedUrl(_w('original'), 290), _w('w342'));
    });

    test('la plus petite largeur qui couvre 90 % du besoin, bornes comprises', () {
      expect(tmdbSizedUrl(_w('original'), 80), _w('w92'));
      expect(tmdbSizedUrl(_w('original'), 102), _w('w92')); // 91,8 ≤ 92
      expect(tmdbSizedUrl(_w('original'), 103), _w('w154')); // 92,7 > 92
      expect(tmdbSizedUrl(_w('original'), 380), _w('w342')); // 342 = 0,9 × 380
      expect(tmdbSizedUrl(_w('original'), 381), _w('w500'));
      expect(tmdbSizedUrl(_w('original'), 1280), _w('w1280'));
      expect(tmdbSizedUrl(_w('original'), 1422), _w('w1280'));
    });

    test('mesure AVD téléphone : vignette décodée à 360 px → w342, plus w500', () {
      expect(tmdbSizedUrl(_poster, 360), _w('w342'));
      expect(tmdbSizedUrl(_poster, 380), _w('w342'));
      expect(tmdbSizedUrl(_poster, 400), _w('w500'));
      expect(tmdbSizedUrl(_poster, 432), _w('w500'));
      expect(tmdbSizedUrl(_w('w1280'), 594), _w('w780'));
    });

    test('fond de fiche décodé à 720 px : w1280 → w780', () {
      expect(tmdbSizedUrl(_w('w1280'), 720), _w('w780'));
    });

    test("⛔ jamais sous 90 % du besoin, quelle que soit l'image de départ", () {
      final List<String> froms = [_poster, _w('original'), _w('w1280'), _w('w780'), _w('w500'), _w('w342'), _w('w185'), _w('w92')];
      for (int need = 1; need <= 1422; need++) {
        for (final String from in froms) {
          final String out = tmdbSizedUrl(from, need);
          if (out == from) continue; // image gardée : ce n'est pas une réécriture
          final int w = int.parse(RegExp(r'/t/p/w(\d+)/').firstMatch(out)!.group(1)!);
          expect(w, greaterThanOrEqualTo(need * kTmdbDownscaleTolerance), reason: 'besoin $need, $from → $out');
        }
      }
    });

    test("une image gardée « assez grande » n'est jamais remplacée par plus petite qu'elle sous 90 %", () {
      for (int need = 1; need <= 1500; need++) {
        for (final String from in [_poster, _w('w500'), _w('w342'), _w('w185')]) {
          final String out = tmdbSizedUrl(from, need);
          final int before = int.parse(RegExp(r'/t/p/w(\d+)').firstMatch(from)!.group(1)!);
          final int after = int.parse(RegExp(r'/t/p/w(\d+)').firstMatch(out)!.group(1)!);
          if (after < before) {
            expect(after, greaterThanOrEqualTo(need * kTmdbDownscaleTolerance), reason: 'besoin $need, $from → $out');
          }
        }
      }
      expect(kTmdbDownscaleTolerance, greaterThanOrEqualTo(kTmdbUpscaleTolerance));
    });

    test('un besoin au-delà de w1280 garde une image plus grande intacte', () {
      expect(tmdbSizedUrl(_w('original'), 1500), _w('original'));
      expect(tmdbSizedUrl(_w('w1280'), 1500), _w('w1280'));
    });

    test('ne réécrit pas quand ça n\'allège rien (déjà à la bonne taille)', () {
      expect(tmdbSizedUrl(_w('w342'), 290), _w('w342'));
      expect(tmdbSizedUrl(_w('w500'), 400), _w('w500'));
      // 600 couvre 560 : la réécriture donnerait w780, plus lourd.
      expect(tmdbSizedUrl(_poster, 560), _poster);
    });
  });

  group('tmdbSizedUrl — monter une image nettement trop petite', () {
    test('w185 (liste racine) pour une vignette de 290 px → w342', () {
      expect(tmdbSizedUrl(_w('w185'), 290), _w('w342'));
    });

    test('photo d\'acteur w342 pour un en-tête décodé à 720 px → w780', () {
      expect(tmdbSizedUrl(_w('w342'), 720), _w('w780'));
    });

    test('au-delà de l\'échelle, on monte au plus haut : w1280', () {
      expect(tmdbSizedUrl(_w('w185'), 2000), _w('w1280'));
    });

    test('⚠️ à moins de 15 % du besoin, on ne monte pas (l\'écart ne se voit pas)', () {
      // Affiche du hero : 600 px pour un décodage à 640 → garder 600.
      expect(tmdbSizedUrl(_poster, 640), _poster);
      expect(tmdbSizedUrl(_w('w500'), 560), _w('w500'));
      // 500 < 0,85 × 600 = 510 → trop petite, on monte.
      expect(tmdbSizedUrl(_w('w500'), 600), _w('w780'));
    });
  });

  group('tmdbSizedUrl — ce qui ne se touche pas', () {
    test('sans largeur connue : inchangé', () {
      expect(tmdbSizedUrl(_poster, null), _poster);
      expect(tmdbSizedUrl(_poster, 0), _poster);
    });

    test('hôtes non TMDB : inchangés', () {
      const String imgur = 'https://i.imgur.com/vPb5DQA.png';
      const String panel = 'http://panel.example:8080/images/w600_and_h900_bestv2/a.jpg';
      expect(tmdbSizedUrl(imgur, 290), imgur);
      expect(tmdbSizedUrl(panel, 290), panel);
    });

    test('cadrages rognés ou réglés en hauteur : inchangés', () {
      final String face = _w('w220_and_h330_face');
      final String faces = _w('w1920_and_h800_multi_faces');
      final String h = _w('h632');
      expect(tmdbSizedUrl(face, 100), face);
      expect(tmdbSizedUrl(faces, 290), faces);
      expect(tmdbSizedUrl(h, 290), h);
    });

    test('adresse avec paramètres : inchangée', () {
      final String q = '${_w('w1280')}?lang=fr';
      expect(tmdbSizedUrl(q, 290), q);
    });

    test('le schéma est gardé (il décide du cache disque)', () {
      const String http = 'http://image.tmdb.org/t/p/w600_and_h900_bestv2/a.jpg';
      expect(tmdbSizedUrl(http, 290), 'http://image.tmdb.org/t/p/w342/a.jpg');
    });

    test('toute largeur produite est dans l\'échelle vérifiée', () {
      for (final int need in [1, 90, 200, 300, 450, 700, 1100, 5000]) {
        for (final String from in [_poster, _w('w185'), _w('original'), _w('w92')]) {
          final String out = tmdbSizedUrl(from, need);
          final Match? m = RegExp(r'/t/p/w(\d+)/').firstMatch(out);
          if (out == from || m == null) continue;
          expect(kTmdbWidths, contains(int.parse(m.group(1)!)), reason: out);
        }
      }
    });
  });

  group('AetherImage.candidates — l\'adresse d\'origine reste le repli', () {
    test('taille réécrite d\'abord, puis l\'originale, puis les replis', () {
      const String alt = 'https://i.imgur.com/alt.png';
      final AetherImage img = AetherImage(url: _poster, alternates: const [alt], cacheWidth: 290);
      expect(img.candidates, [_w('w342'), _poster, alt]);
    });

    test('chaque repli TMDB a aussi sa taille puis son original', () {
      final AetherImage img = AetherImage(url: 'https://i.imgur.com/a.png', alternates: [_w('w1280')], cacheWidth: 290);
      expect(img.candidates, ['https://i.imgur.com/a.png', _w('w342'), _w('w1280')]);
    });

    test('sans cacheWidth : exactement les adresses d\'avant', () {
      final AetherImage img = AetherImage(url: _poster, alternates: [_w('w1280'), '', _poster]);
      expect(img.candidates, [_poster, _w('w1280')]);
    });

    test('aucun doublon quand la taille est déjà la bonne', () {
      final AetherImage img = AetherImage(url: _w('w342'), cacheWidth: 290);
      expect(img.candidates, [_w('w342')]);
    });
  });
}
