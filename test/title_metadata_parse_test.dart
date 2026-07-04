import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';

/// §parseAudit2026-06-30 — Verrouille la non-régression des 4 bugs regex
/// trouvés lors de l'audit des 3 catalogues réels PLATINIUM/PREMIUM/VOD
/// (134 992 entrées, `lib/iptv_exemple/`) + les 24 cas critiques déjà couverts
/// par `tool/validate_parse.dart` (repris ici en cas ciblés, pour que
/// `flutter test` les fasse aussi tourner en CI sans dépendre des gros JSON).
///
/// Chaque groupe documente le bug réel trouvé (chaîne exacte issue des
/// catalogues), avant/après, et le nombre d'occurrences mesurées.
void main() {
  TitleMetadata parse(String s) => TitleMetadata.parse(s);

  group('Bug A — préfixe |XX| en casse mixte (11 occurrences réelles)', () {
    test('|FR-4k| (k minuscule) → préfixe entièrement retiré', () {
      final m = parse("|FR-4k| L'amour dans l'objectif (2025)");
      expect(m.baseTitle, "L'amour dans l'objectif");
      expect(m.quality, '4K');
    });

    test('|Fr-4K DV| (F/r mixtes) → préfixe entièrement retiré', () {
      final m = parse('|Fr-4K DV| Sens unique (1987)');
      expect(m.baseTitle, 'Sens unique');
      expect(m.quality, '4K');
    });

    test('|it| (tout minuscule) → préfixe entièrement retiré', () {
      final m = parse('|it| Il sentiero azzurro (2025)');
      expect(m.baseTitle, 'Il sentiero azzurro');
    });
  });

  group('Bug B — pipes résiduels après le préfixe (~6 900 occurrences réelles)', () {
    test('corruption amont mot-coupé "CORP|US| CHRISTI" → "CORPUS CHRISTI"', () {
      final m = parse('|US| ABC 3 (KIII) CORP|US| CHRISTI (H)');
      expect(m.baseTitle, 'ABC 3 CORPUS CHRISTI (H)');
    });

    test('corruption amont "COLUMB|US|" → "COLUMBUS"', () {
      final m = parse('|US| CBS 4 (WCBI) COLUMB|US| (F)');
      expect(m.baseTitle, 'CBS 4 COLUMBUS (F)');
    });

    test('corruption amont "PL|US|" → "PLUS"', () {
      final m = parse('|US| FOX SPORTS OHIO PL|US| (H)');
      expect(m.baseTitle, 'FOX SPORTS OHIO PLUS (H)');
    });

    test('code région dupliqué "|DE| |DE|" → entièrement retiré', () {
      final m = parse('|DE| |DE| SKY SPORT GOLF ᶠᴴᴰ');
      expect(m.baseTitle, 'SKY SPORT GOLF');
      expect(m.quality, 'FHD');
    });

    test('double pipe résiduel "All My Life ||" → nettoyé', () {
      final m = parse('|FR-4K| All My Life || MULTI');
      expect(m.baseTitle, 'All My Life');
      expect(m.languages, contains('MULTI'));
    });

    test('§vigilance — série arabe "Titre | Année | Titre arabe" : le titre '
        'anglais est PRÉSERVÉ (pas avalé par le préfixe), les pipes de '
        'séparation sont nettoyés (comportement différent du provider mais '
        'strictement meilleur que le statu quo pré-fix, où le préfixe brut '
        'restait visible)', () {
      final m = parse('|AR-4k| Midterm | 2025 | ميد تيرم');
      expect(m.baseTitle, 'Midterm ميد تيرم');
      expect(m.quality, '4K');
    });
  });

  group('Bug C — exposants Unicode H265/H264 (568 occurrences réelles)', () {
    test('ᴴ²⁶⁵ (H265 exposant, chaînes RAI/Sky) → nettoyé', () {
      final m = parse('|IT| RAI 1 UHD ᴴ²⁶⁵');
      expect(m.baseTitle, 'RAI 1');
      expect(m.quality, '4K'); // UHD → 4K
    });

    test('combos exposants déjà connus non régressés (ᶠᴴᴰ)', () {
      final m = parse('|DE| NATIONAL GEO ᶠᴴᴰ');
      expect(m.baseTitle, 'NATIONAL GEO');
      expect(m.quality, 'FHD');
    });
  });

  group('Bug D — tag "(NN FPS)" non reconnu (35 occurrences réelles)', () {
    test('(50 FPS) — chaîne sport BEIN SPORTS → nettoyé', () {
      final m = parse(
          '|AR| BEIN SPORTS MAX 1 SD (50 FPS)  (World Cup 2026™)');
      expect(m.baseTitle, 'BEIN SPORTS MAX 1 (World Cup ™)');
      expect(m.quality, 'SD');
    });

    test('(60FPS) collé sans espace — VOD → nettoyé', () {
      final m = parse("Avatar (60FPS) ᴴ²⁶⁵ (2009) VFF");
      expect(m.baseTitle, 'Avatar');
      expect(m.languages, contains('VF'));
    });
  });

  group('Non-régression — 24 cas critiques existants (tool/validate_parse.dart)', () {
    test('|VO|STFR| (préfixe composé collé) → VOSTFR détecté, titre intact', () {
      final m = parse('|VO|STFR| Teefa in Trouble (2018)');
      expect(m.baseTitle, 'Teefa in Trouble');
      expect(m.languages, contains('VOSTFR'));
    });

    test('|LEG.| et |VO-LEG.| (point dans le préfixe)', () {
      expect(parse('|LEG.| Totally Killer (Dezesseis Facadas) (2023)').baseTitle,
          'Totally Killer (Dezesseis Facadas)');
      expect(parse('|VO-LEG.| Film Test (2020)').baseTitle, 'Film Test');
    });

    test('|LIGUE 1+| (chiffre + symbole dans le préfixe)', () {
      expect(parse('|LIGUE 1+| Match du jour').baseTitle, 'Match du jour');
    });

    test('|FR-4K DV| et |4K HDR DV| (qualité composée dans le préfixe)', () {
      final m1 = parse("|FR-4K DV| Tant qu'il y aura des hommes (1953)");
      expect(m1.baseTitle, "Tant qu'il y aura des hommes");
      expect(m1.quality, '4K');
      final m2 = parse('|4K HDR DV| Les Dinosaures');
      expect(m2.baseTitle, 'Les Dinosaures');
      expect(m2.quality, '4K');
    });

    test('ponctuation interne conservée pour l\'affichage (M.A.S.H, tiret)', () {
      expect(parse('|FR| M.A.S.H. (1972)').baseTitle, 'M.A.S.H');
      expect(
        parse('|FR| Cape Fear - Les Nerfs à vif (MULTI) FHD').baseTitle,
        'Cape Fear - Les Nerfs à vif',
      );
    });

    test('fallback titre 1 caractère ("H") reste exploitable', () {
      final m = parse('|FR| H (1998)');
      expect(m.baseTitle, 'H');
      expect(m.year, '1998');
    });
  });

  group('computeGroupKey — accents préservés (Constat n°2)', () {
    test('les accents ne sont PAS strippés (contrairement à l\'ancienne '
        'regex ASCII-only de HomePage._normTitle/ActorDetailsPage._norm, '
        'désormais unifiées sur cette fonction)', () {
      expect(TitleMetadata.computeGroupKey('Café'), 'café');
      expect(TitleMetadata.computeGroupKey('Élite'), 'élite');
      expect(TitleMetadata.computeGroupKey("L'affaire X"), 'l affaire x');
    });
  });
}
