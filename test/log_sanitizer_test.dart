import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/log_sanitizer.dart';

/// §tourFix — [redactUrl] est le filet de sécurité de TOUT log qui mentionne
/// une URL IPTV : le journal §tvLogs est servi en HTTP sur le LAN, donc chaque
/// forme d'URL Xtream qui traverse intacte est une fuite de credentials.
///
/// Le piège couvert ici : la forme NUE `/{user}/{pass}/{id}[.ext]` (sans
/// préfixe live|movie|series|timeshift, documentée dans
/// `XtreamCredentials.tryExtract`) traversait la rédaction intacte.
///
/// ⚠️ **L'extension est OPTIONNELLE** — une première version de la règle
/// l'exigeait, et laissait donc fuir les chaînes TV des playlists « Ultimate »,
/// servies en URL nue sans extension (`http://serveur/{user}/{pass}/9541`),
/// c'est-à-dire le cas le plus nombreux du catalogue. Le test
/// « sans extension » ci-dessous est là pour que ça ne revienne jamais.
///
/// La règle reste étroite (exactement 3 segments, dernier = id numérique, user
/// et pass sans point) pour ne pas détruire les paths d'API innocents.
void main() {
  group('redactUrl — forme Xtream NUE /{user}/{pass}/{id}[.ext]', () {
    test('SANS extension (chaîne TV Ultimate) — le cas qui fuyait', () {
      const url = 'http://serveur.tv:8080/jean/s3cr3t/9541';
      final out = redactUrl(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('serveur.tv'));
      expect(out, contains('9541'));
      expect(out, contains('/***/***/'));
    });

    test('user et pass masqués, host et id conservés', () {
      const url = 'http://panel.example.com:8080/jean/s3cr3t/12345.mkv';
      final out = redactUrl(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('panel.example.com'));
      // L'id du flux reste lisible : c'est lui qui a une valeur de diagnostic.
      expect(out, contains('12345.mkv'));
      expect(out, contains('/***/***/'));
    });

    test('extension .ts (flux TV) masquée aussi', () {
      final out = redactUrl('http://host.tv:8080/jean/s3cr3t/987.ts');
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('987.ts'));
    });
  });

  group('redactUrl — comportements existants intacts', () {
    test('forme préfixée /movie/{user}/{pass}/{id} toujours masquée', () {
      const url = 'http://panel.example.com:8080/movie/jean/s3cr3t/12345.mkv';
      final out = redactUrl(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('/movie/***/***/12345.mkv'));
    });

    test('timeshift : segments credentials toujours masqués', () {
      const url =
          'http://host.tv:8080/timeshift/jean/s3cr3t/120/2026-08-14:20-00/55.ts';
      final out = redactUrl(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
    });

    test('query username/password toujours masqués', () {
      const url =
          'http://panel.example.com/get.php?username=jean&password=s3cr3t&type=m3u_plus';
      final out = redactUrl(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      // Le type de playlist reste lisible.
      expect(out, contains('m3u_plus'));
    });
  });

  group('redactUrl — pas de faux positif', () {
    test('path 3 segments innocent /api/v2/status.json traverse INTACT', () {
      // `status.json` n'est pas un id numérique : la règle NUE ne doit pas se
      // déclencher, sinon `v2` serait détruit.
      const url = 'http://api.example.com/api/v2/status.json';
      expect(redactUrl(url), url);
    });

    test('segment à extension en position user/pass → pas de masquage', () {
      // Le garde-fou repris de `tryExtract` : un vrai identifiant ne contient
      // pas de point. Sans lui, l'acceptation de l'id SANS extension ferait
      // masquer des chemins de fichiers ordinaires.
      const url = 'http://cdn.example.com/assets/logo.png/42';
      expect(redactUrl(url), url);
    });
  });
}
