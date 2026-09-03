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
      // §tagResidue (2026-08-30) — L'attente était `ABC 3 CORPUS CHRISTI (H)`.
      // `(KIII)` disparaissait par ACCIDENT : `_reLangParens` s'écrivait
      // `[A-Z]{2,6}` en `caseSensitive: false`, donc elle mangeait n'importe
      // quel mot de 2 à 6 lettres — y compris `[REC]`, qui est un vrai titre.
      // La liste est fermée ; `KIII` est l'indicatif de la station, il reste.
      expect(m.baseTitle, 'ABC 3 (KIII) CORPUS CHRISTI (H)');
    });

    test('corruption amont "COLUMB|US|" → "COLUMBUS"', () {
      final m = parse('|US| CBS 4 (WCBI) COLUMB|US| (F)');
      // §tagResidue — Même raison que ci-dessus : `WCBI` est un indicatif.
      expect(m.baseTitle, 'CBS 4 (WCBI) COLUMBUS (F)');
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
      // §tagResidue — L'attente était `(World Cup ™)`, c'est-à-dire le nom de
      // l'épreuve AMPUTÉ de son année. Un groupe conservé est désormais masqué
      // pendant le strip, donc `_stripYears` ne peut plus l'entamer : on lit
      // `World Cup 2026`, le vrai nom. Même famille que §midYear — une année
      // qui fait partie d'un nom n'est pas une date de sortie.
      expect(m.baseTitle, 'BEIN SPORTS MAX 1 (World Cup 2026™)');
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

  group('computeGroupKey — accents REPLIÉS (§searchAccents, ex-Constat n°2)', () {
    test('les accents sont repliés sur leur lettre de base, jamais tronqués',
        () {
      // ⚠️ Ce test remplace « accents préservés » (Constat n°2, 2026-06-30) —
      // et ne le contredit PAS. Ce qui avait été rejeté à l'époque, c'était la
      // regex ASCII-only de `HomePage._normTitle`, qui **tronquait** au premier
      // caractère non-ASCII : « Café » devenait « caf ». Elle DÉTRUISAIT de
      // l'information et faisait échouer silencieusement le matching TMDB.
      //
      // §searchAccents **replie** au lieu de tronquer : « Café » → « cafe ».
      // L'information est conservée, et la clé devient insensible aux accents —
      // ce dont la recherche a besoin, puisque 18 % des titres des listes
      // réelles en portent un et que personne ne les tape au clavier.
      expect(TitleMetadata.computeGroupKey('Café'), 'cafe');
      expect(TitleMetadata.computeGroupKey('Élite'), 'elite');
      expect(TitleMetadata.computeGroupKey("L'affaire X"), 'l affaire x');
    });

    test("rien n'est TRONQUÉ — c'était le vrai défaut de l'ancienne regex", () {
      expect(TitleMetadata.computeGroupKey('Café').length, 4);
      expect(TitleMetadata.computeGroupKey('Élite').length, 5);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // §xenoFormat — 4e fournisseur : preffixe a pipe FERMANT seul + [MULTI-SUB]
  // ════════════════════════════════════════════════════════════════════════
  group("xenoFormat — prefixe 'XX| ' (pipe fermant seul)", () {
    test("le prefixe est retire du titre ET de la cle", () {
      final m = TitleMetadata.parse("FR| Lanterns");
      expect(m.baseTitle, "Lanterns");
      expect(m.groupKey, "lanterns");
    });

    test("LE cas signale : les deux formes convergent sur la MEME cle", () {
      // Cette liste ecrit la meme serie de deux facons. Sans les DEUX
      // correctifs (prefixe + [MULTI-SUB]), elles restaient deux vignettes.
      expect(TitleMetadata.parse("FR| Lanterns").groupKey,
          TitleMetadata.parse("Lanterns [MULTI-SUB]").groupKey);
    });

    test("fusion cross-listes : avec et sans prefixe", () {
      expect(TitleMetadata.parse("FR| Rush Hour 3").groupKey,
          TitleMetadata.parse("Rush Hour 3").groupKey);
    });

    test("le code pays part dans providerTag, PAS dans versionLabel", () {
      // Sans discriminant, les deux versions fusionnees afficheraient deux
      // boutons identiques dans l'action sheet -> le code pays doit survivre.
      // Mais il a son PROPRE champ : verse dans versionLabel (fourre-tout que
      // l'UI lit comme une qualite), il s'affichait « Regarder · FR ».
      final m = TitleMetadata.parse("FR| Lanterns");
      expect(m.providerTag, "FR");
      expect(m.versionLabel, isNull);
    });

    test("le marqueur est extrait AUSSI de la forme encadree", () {
      // Incoherence corrigee au passage : `|FR|` perdait le code, `FR| ` le
      // gardait -> versions distinguables une fois sur deux seulement.
      expect(TitleMetadata.parse("|FR| TF1 HD").providerTag, "FR");
    });

    test("marqueurs d'autres pays / rubriques", () {
      // « la qualite n'est pas une langue » : aucun de ces marqueurs ne doit
      // ressortir en qualite.
      for (final e in {
        "IT| Rai 1": "IT",
        "RU| Match TV": "RU",
        "US| CNN": "US",
        "24/7-AR| Nature": "24/7-AR",
      }.entries) {
        final m = TitleMetadata.parse(e.key);
        expect(m.providerTag, e.value, reason: e.key);
        expect(m.quality, isNull, reason: "${e.key} : pas une qualite");
      }
    });

    test("codes composes et casse libre", () {
      expect(TitleMetadata.parse("24/7-AR| Nature").baseTitle, "Nature");
      expect(TitleMetadata.parse("EXYU| RTS 1 HD").baseTitle, "RTS 1");
      // Typo fournisseur reelle : le pipe ouvrant remplace par un 'l'.
      expect(TitleMetadata.parse("lAR| Albar Altani -2016").baseTitle,
          "Albar Altani");
    });

    test("ANTI-REGRESSION : un vrai titre suivi d'un pipe n'est PAS mange", () {
      // `Sneakers|BRUTX|(FR) FHD 2022` (PREMIUM, 7 occurrences reelles) : le
      // TITRE est « Sneakers ». C'est l'ABSENCE d'espace apres le pipe qui
      // distingue ce cas d'un vrai prefixe pays — ne jamais relacher ce point.
      expect(TitleMetadata.parse("Sneakers|BRUTX|(FR) FHD 2022").baseTitle,
          contains("Sneakers"));
      expect(TitleMetadata.parse("Requin|BRUTX| (FR) FHD 2021").baseTitle,
          contains("Requin"));
    });

    test("non-regression : la forme encadree |FR| reste geree", () {
      expect(TitleMetadata.parse("|FR| TF1 HD").baseTitle, "TF1");
    });
  });

  group("xenoFormat — famille [MULTI-SUB]", () {
    test("le tag composite ne laisse aucun residu", () {
      // Avant : `_reLangTags` retirait MULTI seul et laissait « [-SUB] ».
      for (final raw in [
        "Senna [MULTI-SUB]",
        "Senna [MULTI_SUB]",
        "Senna [MULTI-AUDIO]",
        "Senna [MULTI-SUB-AUDIO]",
        "Senna [MULTI-SUB/AUDIO]",
      ]) {
        expect(TitleMetadata.parse(raw).baseTitle, "Senna", reason: raw);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // §yearTitle — un titre qui EST une annee
  // ════════════════════════════════════════════════════════════════════════
  group("yearTitle — une annee en tete n'est pas une date de sortie", () {
    test("LE bug signale : le film 2067 s'affichait « (FR HD) »", () {
      final m = TitleMetadata.parse("2067 (FR) FHD 2020");
      expect(m.baseTitle, "2067");
      expect(m.year, "2020"); // et non 2067
    });

    test("meme titre, autre fournisseur", () {
      final m = TitleMetadata.parse("2067 (2020) (FHD MULTi)");
      expect(m.baseTitle, "2067");
      expect(m.year, "2020");
    });

    test("le titre EST l'annee, et rien d'autre", () {
      final m = TitleMetadata.parse("1917");
      expect(m.baseTitle, "1917");
      expect(m.year, isNull); // aucune date a afficher
    });

    test("annee en tete + vraie annee entre parentheses", () {
      final m = TitleMetadata.parse("|FR| 1941 (1979)");
      expect(m.baseTitle, "1941");
      expect(m.year, "1979");
    });

    test("annee en tete suivie de texte", () {
      expect(TitleMetadata.parse("FR| 2025 Armageddon").baseTitle,
          "2025 Armageddon");
    });

    test("non-regression : annee normale en fin de titre", () {
      final m = TitleMetadata.parse("Michael (2026) [MULTi]");
      expect(m.baseTitle, "Michael");
      expect(m.year, "2026");
    });
  });

  // §orphanBracket — Delimiteur ferme sans avoir ete ouvert.
  group("orphanBracket", () {
    test("cas signale : pipe ouvrant, crochet fermant", () {
      // Entree REELLE (xenoIptv) : le fournisseur ouvre le tag avec `|` et le
      // referme avec `]`. Le `]` orphelin restait dans le titre AFFICHE, et
      // faisait echouer la soustraction qui calcule versionLabel -> tout le
      // titre repartait dans le libelle (« FR Spider-Man… »).
      final m = TitleMetadata.parse("FR| Spider-Man : Brand New Day - 2026 |HDTS]");
      expect(m.baseTitle, "Spider-Man : Brand New Day");
      expect(m.providerTag, "FR"); // §providerTag — pas une qualite
      expect(m.quality, "CAM"); // §camQuality — HDTS EST une qualite
      expect(m.year, "2026");
    });

    test("fusionne avec la variante bien formee de la meme liste", () {
      // Les deux entrees coexistent chez le fournisseur : une seule vignette.
      expect(
        TitleMetadata.parse("FR| Spider-Man : Brand New Day - 2026 |HDTS]").groupKey,
        TitleMetadata.parse("FR| Spider-Man: Brand New Day - 2026 [VOSTFR] [HDCAM]").groupKey,
      );
    });

    test("non-regression §23b : une PAIRE legitime est conservee", () {
      // Le trim du titre d'affichage epargne volontairement les crochets pour
      // ce titre precis : le nettoyage ne doit viser que les orphelins.
      expect(TitleMetadata.parse("Totally Killer (Dezesseis Facadas)").baseTitle,
          "Totally Killer (Dezesseis Facadas)");
    });

    test("ouvrant jamais referme", () {
      expect(TitleMetadata.parse("|QC| Mere Ordinaire 2 [2021) (VFQ)").baseTitle,
          "Mere Ordinaire 2");
    });

    test("fermant en trop au milieu du titre", () {
      expect(
        TitleMetadata.parse("|FR| Final Fantasy XV : Kingsglaive (2016)) |MULTI| VFF")
            .baseTitle,
        "Final Fantasy XV : Kingsglaive",
      );
    });
  });

  // §camQuality — Les rips de salle sont une qualite, la pire.
  group("camQuality", () {
    test("HDTS / HDCAM sont detectes comme qualite", () {
      // `hd` ne matche pas « HDTS » : ces titres ressortaient SANS
      // qualite du tout, alors que c'est l'info la plus utile a montrer.
      expect(TitleMetadata.parse("Film [HDTS]").quality, "CAM");
      expect(TitleMetadata.parse("Film [HDCAM]").quality, "CAM");
      expect(TitleMetadata.parse("Film CAMRIP").quality, "CAM");
    });

    test("le rip prime sur la resolution annoncee", () {
      // Un « 1080p HDCAM » reste filme dans une salle.
      expect(TitleMetadata.parse("Film 1080p HDCAM").quality, "CAM");
    });

    test("non-regression : les resolutions normales sont intactes", () {
      expect(TitleMetadata.parse("Film FHD").quality, "FHD");
      expect(TitleMetadata.parse("Film 4K").quality, "4K");
      expect(TitleMetadata.parse("Film HD").quality, "HD");
    });
  });

  // §labelLeak — Le libelle de version ne doit JAMAIS contenir le titre.
  group("labelLeak", () {
    test("double espace dans le titre", () {
      // Le libelle etait calcule en soustrayant le titre NETTOYE du titre brut,
      // par sous-chaine litterale : les espaces recollapses suffisaient a faire
      // echouer la soustraction, et tout le titre repartait en libelle.
      final m = TitleMetadata.parse("|FR| Flicka 3  Meilleures amies (2012)");
      expect(m.baseTitle, "Flicka 3 Meilleures amies");
      expect(m.versionLabel, isNull);
    });

    test("annee au MILIEU du titre", () {
      expect(
        TitleMetadata.parse("|FR| Star Ac Tour 2026, le concert (2026)")
            .versionLabel,
        isNull,
      );
    });

    test("ponctuation de bord (le titre perd son point final)", () {
      // base = « Jane B. par Agnes V » (point final trime) alors que le brut
      // garde « V. » -> le mot ne s'appariait pas et « V » sortait en libelle.
      expect(TitleMetadata.parse("|FR| Jane B. par Agnes V. (1988)").versionLabel,
          isNull);
    });

    test("un VRAI libelle de version survit", () {
      // C'est tout l'interet de ne pas simplement vider le champ.
      final m = TitleMetadata.parse(
          "|DE| Rebel Moon: Teil 2: Die Narbenmacherin (2024) (Directors.Cut)");
      expect(m.baseTitle, "Rebel Moon: Teil 2: Die Narbenmacherin");
      expect(m.versionLabel, "Directors.Cut");
      expect(m.providerTag, "DE");
    });
  });

  // §invisibleLead — Marques bidi/BOM en tete de titre.
  group("invisibleLead", () {
    test("un LRM en tete n'empeche plus la lecture du prefixe", () {
      // Dart ne traite pas U+200E comme une espace : le `^\s*` des regex de
      // prefixe ne le franchissait pas, donc « FR- » restait dans le titre.
      final m = TitleMetadata.parse("‎|FR-4K DV| On s'attache ? (2025)");
      expect(m.baseTitle, "On s'attache ?");
      expect(m.providerTag, "FR");
      expect(m.quality, "4K");
    });
  });

  // §midYear — Une annee NUE au milieu d'un titre appartient au TITRE.
  group("tagResidue", () {
    // §tagResidue — Un groupe entamé par le strip laissait ses débris DANS la
    // clé de regroupement, donc le titre ne fusionnait plus entre listes.
    // Mesuré : 1 266 titres sur 353 475 avant correctif, 0 après.
    test("groupe entame -> retire en entier, pas a moitie", () {
      expect(TitleMetadata.parse("Toy Story 5 (2026) [MULTi VQF/VO]").baseTitle,
          "Toy Story 5");
      expect(
          TitleMetadata.parse("Superman (2025) [4K HDR10+ Dolby A/V]").baseTitle,
          "Superman");
      expect(
          TitleMetadata.parse(
                  "Un homme en colere (2021) [FHD MULTi Audio/Subs]")
              .baseTitle,
          "Un homme en colere");
    });

    test("un debris ne devient jamais un libelle de version", () {
      // Sans le filtre final, la pastille de version affichait « A/V ».
      expect(
          TitleMetadata.parse("Superman (2025) [4K HDR10+ Dolby A/V]")
              .versionLabel,
          isNull);
    });

    test("un groupe JAMAIS touche par le strip reste intact", () {
      // La garantie du correctif : aucun jeton connu dedans -> on n'y touche pas.
      for (final raw in [
        "Totally Killer (Dezesseis Facadas) (2023)",
        "|FR| Aucun homme ni dieu (Hold The Dark) (2018)",
        "The Meg (3D) MULTI 2018",
        "|NO| V SPORT 1 ( S ) HD",
      ]) {
        expect(TitleMetadata.parse(raw).baseTitle, contains("("), reason: raw);
      }
    });

    test("[REC] est un VRAI titre, pas un code langue", () {
      // Signale en seance. `_reLangParens` le detruisait : le titre devenait
      // vide et le repli rendait alors le titre BRUT, tags compris.
      final m = TitleMetadata.parse("[REC] (2007) [MULTi]");
      expect(m.baseTitle, "[REC]");
      expect(m.groupKey, "rec");
    });

    test("LEGO ne doit pas etre ampute par le jeton LEG", () {
      expect(
          TitleMetadata.parse("|AR| LEGO Marvel Super Heroes (2013)").baseTitle,
          "LEGO Marvel Super Heroes");
    });

    test("une annee entre delimiteurs reste lisible par _stripYears", () {
      // La retirer trop tot faisait passer 1965 pour la date de sortie.
      expect(TitleMetadata.parse("|FR| Valensole 1965 (2025)").baseTitle,
          "Valensole 1965");
    });
  });

  group("midYear", () {
    test("le cas signale : l'annee fait partie du nom", () {
      final m = TitleMetadata.parse(
          "|FR| Star Ac Tour 2026, le concert evenement (2026)");
      expect(m.baseTitle, "Star Ac Tour 2026, le concert evenement");
      expect(m.year, "2026"); // la VRAIE date est celle entre parentheses
    });

    test("autres titres reels ampute par l'ancienne regle", () {
      expect(TitleMetadata.parse("|FR| Valensole 1965 (2025)").baseTitle,
          "Valensole 1965");
      expect(TitleMetadata.parse("|FR| WWE SummerSlam 2025 - Sunday (2025)").baseTitle,
          "WWE SummerSlam 2025 - Sunday");
      expect(
          TitleMetadata.parse("|FR| Roland-Garros, une edition 2025 inoubliable (2025)")
              .baseTitle,
          "Roland-Garros, une edition 2025 inoubliable");
    });

    test("annee NUE en FIN = date de sortie (16 128 cas)", () {
      final m = TitleMetadata.parse("|FR| Adios Amigos | 2016");
      expect(m.baseTitle, "Adios Amigos");
      expect(m.year, "2016");
    });

    test("annee entre PIPES = date de sortie (separateur de champs)", () {
      // Seul contre-exemple reel a « annee nue au milieu = titre » : le pipe
      // est un separateur de champs chez ces fournisseurs, jamais de la prose.
      final m = TitleMetadata.parse("|AR-4k| Midterm | 2025 | Titre");
      expect(m.baseTitle, "Midterm Titre");
      expect(m.year, "2025");
    });

    test("annee delimitee EN TETE = date, pas titre", () {
      // Ces titres arabes collent la date au 1er mot, sans espace.
      final m = TitleMetadata.parse("(2016)Le Titre");
      expect(m.baseTitle, "Le Titre");
      expect(m.year, "2016");
    });

    test("non-regression §yearTitle : le titre EST l'annee", () {
      expect(TitleMetadata.parse("1917").baseTitle, "1917");
      expect(TitleMetadata.parse("1917").year, isNull);
      final m = TitleMetadata.parse("2067 (FR) FHD 2020");
      expect(m.baseTitle, "2067");
      expect(m.year, "2020");
    });
  });

  // §keep3d — « 3D » fait partie du titre bien plus souvent qu'il n'est un tag.
  group("keep3d", () {
    test("3D reste dans le titre", () {
      // 65 titres reels en contiennent, presque tous dans leur NOM.
      expect(TitleMetadata.parse("|FR| Winx Club 3D: L'Aventure Magique (2010)").baseTitle,
          "Winx Club 3D: L'Aventure Magique");
      expect(TitleMetadata.parse("|FR| Texas Chainsaw 3D (2013)").baseTitle,
          "Texas Chainsaw 3D");
      expect(TitleMetadata.parse("|FR| Saw 3D : Chapitre final (2010)").baseTitle,
          "Saw 3D : Chapitre final");
    });

    test("le marqueur de FORMAT vit dans le prefixe, pas dans le titre", () {
      final m = TitleMetadata.parse("|DE-3D| Black Panther (2018)");
      expect(m.baseTitle, "Black Panther");
      expect(m.providerTag, "DE-3D");
    });
  });

  // §midYearFix — L'annee doit survivre a ce qui SUIT (tags, balises inconnues,
  // separateurs). Sans ca, TMDB perd son principal desambiguisateur.
  group("midYearFix", () {
    test("tag [MULTI-SUB] apres l'annee (cas signale)", () {
      // Regression introduite le 2026-08-28 : `_extractYear` travaille sur le
      // titre BRUT alors que `_stripYears` recoit un titre deja nettoye. Le
      // `[MULTI-SUB]` restant faisait croire a du texte apres l'annee.
      final m = TitleMetadata.parse("The Whisper Man - 2026 [MULTI-SUB]");
      expect(m.baseTitle, "The Whisper Man");
      expect(m.year, "2026");
    });

    test("balise INCONNUE entre crochets apres l'annee", () {
      // On ne peut pas se reposer sur la liste des tags connus : les
      // fournisseurs en inventent.
      expect(
        TitleMetadata.parse("UFC 329: McGregor vs. Holloway 2 - 2026 [Prelims]").year,
        "2026",
      );
    });

    test("annee encadree par un separateur symetrique", () {
      final m = TitleMetadata.parse("|AR| Lees Baghdad - 2020 - Titre");
      expect(m.year, "2020");
      // Les deux separateurs ne doivent pas rester colles apres le retrait.
      expect(m.baseTitle, "Lees Baghdad - Titre");
      final dots = TitleMetadata.parse("Wrong.Place.2022.lati");
      expect(dots.year, "2022");
      expect(dots.baseTitle, "Wrong.Place.lati");
    });

    test("suffixe PART n apres l'annee", () {
      expect(
        TitleMetadata.parse("Les Papiers de l'Anglais (MULTI) FHD 2024 PART 1").year,
        "2024",
      );
    });

    test("non-regression : le separateur doit encadrer DES DEUX cotes", () {
      // Sinon la regle mangerait l'annee du titre de §midYear.
      expect(TitleMetadata.parse("|FR| WWE SummerSlam 2025 - Sunday (2025)").baseTitle,
          "WWE SummerSlam 2025 - Sunday");
    });

    test("non-regression : ponctuation interne intacte", () {
      expect(TitleMetadata.parse("M.A.S.H").baseTitle, "M.A.S.H");
      expect(TitleMetadata.parse("|FR| Cape Fear - Les Nerfs a vif").baseTitle,
          "Cape Fear - Les Nerfs a vif");
    });
  });

}
