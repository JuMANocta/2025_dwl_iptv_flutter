// §tourFix — revue 2026-09-11, D5A-02 / D1B-03 / D1B-24 — L'INVARIANT
// CROISÉ : ce que `XtreamCredentials.tryExtract` sait EXTRAIRE d'une URL,
// `redactUrl` (et donc `sanitizeForLog`, le puits du journal §tvLogs, persisté
// §logPersist et servi sur le LAN) doit le MASQUER.
//
// CLAUDE.md présentait `log_sanitizer_test.dart` comme le test de cet
// invariant ; il n'appelait jamais `tryExtract`. Deux copies de la règle
// avaient divergé : `/{user}/{pass}/index.m3u8`, `/playlist/{user}/{pass}/…`,
// un slash final… s'extrayaient et traversaient la rédaction en clair.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/diagnostics/log_buffer.dart'
    show sanitizeForLog;
import 'package:aetherStream/core/utils/log_sanitizer.dart';
import 'package:aetherStream/data/models/stream_account.dart';

/// Les segments et valeurs VISIBLES d'une URL masquée : on compare par
/// segment, pas par sous-chaîne (un identifiant « api » apparaît dans l'hôte
/// `api.example.com` sans rien fuir).
List<String> _visibleParts(String redacted) {
  final Uri u = Uri.parse(redacted);
  return <String>[
    ...u.pathSegments,
    ...u.queryParameters.values,
    ...u.userInfo.split(':'),
  ];
}

void main() {
  // Toutes les formes vues dans le code, les fiches de la revue, et les
  // dumps : réelles, limites, et innocentes.
  const List<String> corpus = <String>[
    'http://h:8080/live/jean/s3cr3t/123.ts',
    'http://h:8080/LIVE/jean/s3cr3t/123.ts',
    'http://h:8080/movie/jean/s3cr3t/55.mkv',
    'http://h:8080/series/jean/s3cr3t/77.mp4',
    'http://h:8080/timeshift/jean/s3cr3t/120/2026-08-14:20-00/55.ts',
    'http://h:8080/jean/s3cr3t/9541',
    'http://h:8080/jean/s3cr3t/9541/',
    'http://h:8080//jean//s3cr3t/9541',
    'http://h/jean/s3cr3t/index.m3u8',
    'http://h:8080/playlist/jean/s3cr3t/m3u_plus',
    'http://h/jean/s3cr3t/live/x/y',
    'http://h/get.php?username=jean&password=s3cr3t&type=m3u_plus',
    'http://h/player_api.php?username=jean&password=s3cr3t&action=get_short_epg',
    'http://api.example.com/api/v2/status.json',
    'https://image.tmdb.org/t/p/w500/abc.jpg',
    'http://cdn.example.com/assets/logo.png/42',
    'http://cdn.example.com/a.b/c/d.m3u8',
    'http://h/single.m3u',
  ];

  group('invariant croisé tryExtract ⊆ redactUrl', () {
    for (final String url in corpus) {
      test('ce qui s extrait se masque — $url', () {
        final creds = XtreamCredentials.tryExtract(url);
        if (creds == null) return; // rien d'extrait : rien à exiger
        final List<String> visible = _visibleParts(redactUrl(url));
        expect(visible, isNot(contains(creds.username)));
        expect(visible, isNot(contains(creds.password)));
        // Et au puits du journal, dans une ligne quelconque.
        final String line = sanitizeForLog('GET $url → 200');
        expect(line, isNot(contains('s3cr3t')));
      });
    }

    test('le corpus n est pas vide de sens : les formes réelles s extraient', () {
      for (final String url in <String>[
        'http://h:8080/live/jean/s3cr3t/123.ts',
        'http://h:8080/jean/s3cr3t/9541',
        'http://h/jean/s3cr3t/index.m3u8',
        'http://h:8080/playlist/jean/s3cr3t/m3u_plus',
        'http://h/get.php?username=jean&password=s3cr3t&type=m3u_plus',
      ]) {
        expect(XtreamCredentials.tryExtract(url), isNotNull, reason: url);
      }
    });

    test('⚠️ les deux formes qui fuyaient avant la revue sont masquées', () {
      for (final String url in <String>[
        'http://h/jean/s3cr3t/index.m3u8',
        'http://h/playlist/jean/s3cr3t/m3u_plus',
      ]) {
        expect(redactUrl(url), isNot(contains('s3cr3t')), reason: url);
      }
    });
  });

  group('tryExtract — comportement INCHANGÉ sur les formes réelles', () {
    // La carte Xtream (expiration, connexions), l'API JSON des comptes
    // « URL complète », castUrlFor et le replay en dépendent.
    test('préfixe /live/ : hôte + identifiants', () {
      final c =
          XtreamCredentials.tryExtract('http://h:8080/live/jean/s3cr3t/123.ts')!;
      expect((c.host, c.username, c.password), ('http://h:8080', 'jean', 's3cr3t'));
    });

    test('get.php en query', () {
      final c = XtreamCredentials.tryExtract(
          'http://panel.tv/get.php?username=jean&password=s3cr3t&type=m3u_plus')!;
      expect((c.username, c.password), ('jean', 's3cr3t'));
    });

    test('garde anti-point : un chemin de fichier n est pas un identifiant', () {
      expect(XtreamCredentials.tryExtract('http://cdn.example.com/assets/logo.png/42'),
          isNull);
      expect(XtreamCredentials.tryExtract('http://cdn.example.com/a.b/c/d.m3u8'),
          isNull);
    });

    test('moins de trois segments : rien', () {
      expect(XtreamCredentials.tryExtract('http://h/single.m3u'), isNull);
      expect(XtreamCredentials.tryExtract('http://h/live/jean/s3cr3t'), isNull);
    });
  });

  // R35 — recette Cast du 2026-09-12 : `📡 CastService.start → … http://
  // 192.168.1.70:42789/c689c486…/relay.mp4` dans un journal persisté
  // (§logPersist) et servi sur le LAN (§tvLogs). Le jeton que §castLan avait
  // ajouté pour empêcher un voisin de Wi-Fi d'aspirer le flux était publié par
  // le canal même qu'il devait protéger.
  group('R35 — le jeton de nos serveurs locaux ne sort pas au journal', () {
    // 32 hexadécimaux : la forme exacte de `_newToken()` (16 octets) du relais
    // Cast et du serveur de fichiers Cast.
    const String jeton = '0123456789abcdef0123456789abcdef';

    test('relais Cast — /<jeton>/relay.mp4, la fuite constatée', () {
      final String out = redactUrl('http://192.168.1.20:45678/$jeton/relay.mp4');
      expect(out, isNot(contains('0123456789abcdef')));
      // Ce qui sert au diagnostic reste lisible.
      expect(out, contains('192.168.1.20:45678'));
      expect(out, contains('relay.mp4'));
    });

    test('relais Cast — les autres routes du même serveur', () {
      for (final String route in <String>[
        '/$jeton/relay.m3u8',
        '/$jeton/init.mp4',
        '/$jeton/seg/3.m4s',
      ]) {
        expect(redactUrl('http://10.0.0.5:45678$route'),
            isNot(contains('0123456789abcdef')),
            reason: route);
      }
    });

    test('serveur de fichiers Cast — /local/<jeton>/media.mkv', () {
      expect(redactUrl('http://192.168.1.70:42789/local/$jeton/media.mkv'),
          isNot(contains('0123456789abcdef')));
    });

    test('⚠️ /local/ ne dépend PLUS d un accident de forme', () {
      // Avant R35, ce jeton n'était masqué que parce que le prédicat §tourFix
      // prenait (`local`, `<jeton>`) pour un couple user/pass — un accident
      // qu'un changement de route aurait défait sans prévenir. Ici le premier
      // segment porte un point : le prédicat rend `null` (garde anti-point),
      // donc SEULE la règle du jeton peut masquer.
      const String url = 'http://192.168.1.70:42789/v1.0/'
          '0123456789abcdef0123456789abcdef/media.mkv';
      expect(XtreamCredentials.tryExtract(url), isNull);
      expect(xtreamPathCredentialIndexes(Uri.parse(url).pathSegments), isNull);
      final String out = redactUrl(url);
      expect(out, isNot(contains('0123456789abcdef')));
      expect(out, contains('v1.0'));
    });

    test('console web — le jeton en query (?t=…)', () {
      // 16 caractères de l'alphabet sans ambiguïté (D1B-02).
      const String tk = 'HJKLMNPQRSTUVWXY';
      expect(
          redactUrl('http://192.168.1.70:8080/logs.txt?t=$tk&session=previous'),
          isNot(contains(tk)));
    });

    test('au puits du journal (§tvLogs), dans une ligne quelconque', () {
      final String line = sanitizeForLog(
          'CastService.start (LIVE, video/mp4, depuis 0s) '
          'http://192.168.1.70:42789/$jeton/relay.mp4');
      expect(line, isNot(contains('0123456789abcdef')));
    });

    test('⛔ pas de faux positif : un hachage de CDN PUBLIC reste lisible', () {
      // Mesuré dans les dumps (`lib/iptv_exemple/`) : de vraies chaînes sont
      // servies avec un segment de 32 hexadécimaux. Masquer là rendrait deux
      // chaînes indiscernables au journal sans rien protéger — d'où la borne
      // sur l'adresse d'écoute.
      const String url = 'https://shls-live-ak.akamaized.net/out/v1/'
          '07a6ab2d57b2453a91bbdd2d46b5865a/index_2.m3u8';
      expect(redactUrl(url), contains('07a6ab2d57b2453a91bbdd2d46b5865a'));
    });

    test('⚠️ la ponctuation collée à l URL ne défait pas le masquage', () {
      // Le puits capture l'URL avec une classe qui n'exclut ni le point ni la
      // parenthèse : la ponctuation de fin de phrase entre DANS l'URL. Une
      // règle ancrée sur la valeur entière laissait alors le jeton lisible.
      for (final String line in <String>[
        'console ouverte : http://192.168.1.70:8080/?t=HJKLMNPQRSTUVWXY.',
        'console ouverte (http://192.168.1.70:8080/?t=HJKLMNPQRSTUVWXY),',
        'relais http://192.168.1.20:45678/$jeton/relay.mp4.',
      ]) {
        final String out = sanitizeForLog(line);
        expect(out, isNot(contains('HJKLMNPQRSTUVWXY')), reason: line);
        expect(out, isNot(contains('0123456789abcdef')), reason: line);
      }
    });

    test('sans jeton, une URL locale traverse lisible', () {
      final String out = redactUrl('http://127.0.0.1:8080/logs.txt?session=previous');
      expect(out, contains('logs.txt'));
      expect(out, contains('previous'));
    });

    test('la FORME reconnue comme jeton', () {
      expect(looksLikeLocalServerToken(jeton), isTrue);
      expect(looksLikeLocalServerToken('HJKLMNPQRSTUVWXY'), isTrue);
      // Ce qui n'en est pas : un id de flux, un nom de fichier, un mot, et un
      // hexadécimal trop court pour être un de nos jetons.
      expect(looksLikeLocalServerToken('9541'), isFalse);
      expect(looksLikeLocalServerToken('media.mkv'), isFalse);
      expect(looksLikeLocalServerToken('relay.mp4'), isFalse);
      expect(looksLikeLocalServerToken('local'), isFalse);
      expect(looksLikeLocalServerToken('0123456789abcdef'), isFalse);
    });
  });

  group('le prédicat partagé', () {
    test('rangs (user, pass), préfixe optionnel et insensible à la casse', () {
      expect(xtreamPathCredentialIndexes(['jean', 's3cr3t', '1']),
          (user: 0, pass: 1));
      expect(xtreamPathCredentialIndexes(['Movie', 'jean', 's3cr3t', '1']),
          (user: 1, pass: 2));
      expect(xtreamPathCredentialIndexes(['live', 'jean', 's3cr3t']), isNull);
      expect(xtreamPathCredentialIndexes(['a.b', 'c', 'd']), isNull);
    });
  });

  // ── §subOnline (2026-09-17) — la clé d'API en query ───────────────────────
  //
  // Le trou : les formes Xtream portent sur le CHEMIN, et le masquage par
  // FORME de R35 est borné aux adresses où NOS serveurs écoutent. Une clé
  // d'API part vers un hôte PUBLIC — `sub.wyzie.io` (sous-titres en ligne),
  // `api.themoviedb.org` (TMDB) — et aucune des deux règles ne mordait : la
  // clé de l'utilisateur partait en clair dans le journal persisté
  // (§logPersist), lui-même servi sur le LAN (§tvLogs). Même forme que R35.
  group('§subOnline — une clé d\'API ne sort pas au journal', () {
    test('la clé d\'une URL de sous-titres est masquée, le reste reste lisible',
        () {
      const url =
          'https://sub.wyzie.io/search?id=286217&language=fr&format=srt&key=abc123DEF';
      final out = redactUrl(url);
      expect(out, isNot(contains('abc123DEF')));
      expect(out, contains('key=***'));
      // Ce qui sert à diagnostiquer doit survivre : sans l'identifiant ni la
      // langue, la ligne de journal ne dit plus rien d'utile.
      expect(out, contains('id=286217'));
      expect(out, contains('language=fr'));
    });

    test('la clé TMDB aussi : la règle porte sur le NOM, pas sur l\'hôte', () {
      const url =
          'https://api.themoviedb.org/3/movie/550?api_key=0123456789abcdef';
      final out = redactUrl(url);
      expect(out, isNot(contains('0123456789abcdef')));
      expect(out, contains('api_key=***'));
    });

    test('les variantes de casse et d\'orthographe sont couvertes', () {
      for (final String nom in const ['key', 'API_KEY', 'apiKey', 'token',
        'access_token', 'auth', 'secret']) {
        final out = redactUrl('https://exemple.com/x?$nom=s3cr3t');
        expect(out, isNot(contains('s3cr3t')), reason: 'paramètre « $nom »');
      }
    });

    test('un hôte public sans paramètre sensible n\'est pas touché', () {
      // Sincérité : sans cette assertion, une règle qui masquerait TOUTE la
      // query passerait les tests ci-dessus.
      const url = 'https://exemple.com/x?id=42&lang=fr';
      expect(redactUrl(url), url);
    });

    test('les DEUX voies masquent la même ligne', () {
      // §tvLogs — `sanitizeForLog` est le PUITS : il passe l'URL par
      // `redactUrl`, puis repasse par nom sur le texte libre. Une clé recopiée
      // hors d'une URL (message d'exception tronqué, phrase écrite à la main)
      // doit tomber elle aussi.
      const ligne =
          'échec https://sub.wyzie.io/search?id=1&key=abc123DEF (key: abc123DEF)';
      final out = sanitizeForLog(ligne);
      expect(out, isNot(contains('abc123DEF')),
          reason: 'ni dans l\'URL, ni dans le texte libre');
    });

    test('sanitizeForLog masque api_key sans le confondre avec key', () {
      final out = sanitizeForLog('appel api_key=zzz111 puis key=yyy222');
      expect(out, contains('api_key=***'));
      expect(out, contains('key=***'));
      expect(out, isNot(contains('zzz111')));
      expect(out, isNot(contains('yyy222')));
    });

    test('un mot qui finit par « key » n\'est pas un secret', () {
      // `\b` ne coupe pas au milieu d'un mot : « monkey=3 » n'est pas une clé.
      expect(sanitizeForLog('monkey=3'), contains('monkey=3'));
    });

    test('une URL masquée reste une URL VALIDE, sans crochets ni %2A', () {
      // Défaut trouvé en écrivant les tests ci-dessus : les valeurs de query
      // venant de `queryParametersAll` sont des `List<String>`, et un
      // `v.toString()` les rendait entre crochets — `?id=42` sortait en
      // `?id=%5B42%5D`. Personne ne le voyait : les assertions existantes ne
      // cherchaient qu'une sous-chaîne, et `%5Bm3u_plus%5D` contient encore
      // `m3u_plus`. Une URL recopiée d'un journal était pourtant inutilisable.
      final out = redactUrl(
          'http://panel.example.com/get.php?username=jean&password=s3cr3t&type=m3u_plus');
      expect(out, contains('type=m3u_plus'),
          reason: 'la valeur doit rester telle quelle, sans crochets');
      expect(out, isNot(contains('%5B')));
      expect(out, isNot(contains('%2A')), reason: 'le masque doit se lire');
      expect(out, contains('username=***'));
      expect(out, contains('password=***'));
      // Et elle doit se re-analyser : c'est ça, « rester une URL ».
      final reparse = Uri.parse(out);
      expect(reparse.queryParameters['type'], 'm3u_plus');
      expect(reparse.queryParameters['username'], '***');
    });

    test('un paramètre répété garde sa forme répétée', () {
      // Sincérité du correctif : passer les `List` telles quelles doit rendre
      // `a=1&a=2`, pas `a=1,2` ni `a=%5B1,%202%5D`.
      final out = redactUrl('http://h/x?a=1&a=2');
      expect(Uri.parse(out).queryParametersAll['a'], ['1', '2']);
    });
  });
}
