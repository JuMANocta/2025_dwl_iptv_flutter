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
}
