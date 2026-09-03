// §ramDiet — Verrous de non-régression du parseur M3U **streamé** et du pool
// d'internement de chaînes.
//
// Ce que ces tests protègent, et pourquoi ils existent :
//
//   1. Le parseur ne matérialise plus le fichier (35 Mo de bytes + 70 Mo de
//      String + 75 Mo de lignes, vivants ensemble, sur le thread UI). Il lit
//      `openRead()` → décodeur → `LineSplitter`. Le risque introduit est
//      structurel : les blocs de lecture font 64 Ko et **tombent au milieu des
//      lignes**. Une entrée à cheval sur deux blocs doit sortir intacte.
//   2. Le fallback Latin-1 a changé de forme. En lecture complète, l'échec UTF-8
//      était connu AVANT de produire quoi que ce soit ; en streaming il survient
//      au milieu du flux, après des entrées déjà émises. D'où le parse en listes
//      locales, jetées et relues en Latin-1 — sans jamais publier de doublons.
//   3. La progression se calcule en octets lus, plus en entrées (le comptage
//      préalable relisait tout le fichier pour afficher un pourcentage).
//   4. Le pool partage les valeurs répétitives SANS en changer une seule.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/string_pool.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';

late Directory _tmp;

File _write(String name, List<int> bytes) {
  final f = File('${_tmp.path}/$name')..writeAsBytesSync(bytes);
  return f;
}

/// Construit un M3U de [count] films, volontairement assez gros pour couvrir
/// plusieurs blocs de lecture de 64 Ko.
String _buildM3u(int count) {
  final b = StringBuffer('#EXTM3U\n');
  for (var i = 0; i < count; i++) {
    // Le rembourrage décale les frontières de bloc d'une entrée à l'autre :
    // sur l'ensemble du fichier, la coupure tombe forcément à l'intérieur d'une
    // ligne `#EXTINF` pour certaines entrées — c'est précisément le cas à
    // couvrir, et une longueur fixe ne le garantirait pas.
    final pad = 'x' * (i % 97);
    b.writeln('#EXTINF:-1 tvg-id="id$i" tvg-logo="http://logo/$i.png" '
        'group-title="Films | Action",Le Film $i ($pad) FHD 2020');
    b.writeln('http://srv.test/movie/user/pass/$i.mp4');
  }
  return b.toString();
}

Future<({List<M3uEntry> films, List<M3uEntry> series, List<M3uEntry> tv, List<double> progress})>
    _parse(File f) async {
  final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
  final progress = <double>[];
  await M3uParser.parseFile(f.path, films, series, tv,
      accountId: 'acc-1', onProgress: progress.add);
  return (films: films, series: series, tv: tv, progress: progress);
}

void main() {
  setUpAll(() => _tmp = Directory.systemTemp.createTempSync('m3u_stream_test'));
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  group('Lecture streamée', () {
    test('une entrée à cheval sur deux blocs de 64 Ko reste intacte', () async {
      const count = 4000; // ≈ 600 Ko → une dizaine de blocs
      final f = _write('big.m3u', utf8.encode(_buildM3u(count)));
      expect(f.lengthSync(), greaterThan(64 * 1024 * 4),
          reason: 'le fixture doit couvrir plusieurs blocs de lecture');

      final r = await _parse(f);

      expect(r.films.length, count);
      expect(r.series, isEmpty);
      expect(r.tv, isEmpty);
      // Aucune entrée tronquée : chaque champ de chaque entrée est exact.
      for (var i = 0; i < count; i++) {
        final e = r.films[i];
        expect(e.url, 'http://srv.test/movie/user/pass/$i.mp4');
        expect(e.tvgId, 'id$i');
        expect(e.logoUrl, 'http://logo/$i.png');
        expect(e.groupTitle, 'Films | Action');
        expect(e.title.baseTitle, startsWith('Le Film $i'));
        expect(e.title.year, '2020');
        expect(e.title.quality, 'FHD');
      }
    });

    test('progression monotone, en octets, et terminée à 1.0', () async {
      final f = _write('prog.m3u', utf8.encode(_buildM3u(3000)));
      final r = await _parse(f);

      expect(r.progress.last, 1.0);
      expect(r.progress.length, greaterThan(1),
          reason: 'le pourcentage doit avancer pendant le parsing, '
              'pas sauter de 0 à 1');
      for (final p in r.progress) {
        expect(p, inInclusiveRange(0.0, 1.0));
      }
      for (var i = 1; i < r.progress.length; i++) {
        expect(r.progress[i], greaterThanOrEqualTo(r.progress[i - 1]),
            reason: 'la progression ne doit jamais reculer');
      }
    });

    test('fichier vide ou sans entrée → aucune sortie, pas d\'exception',
        () async {
      final r = await _parse(_write('empty.m3u', utf8.encode('#EXTM3U\n')));
      expect(r.films, isEmpty);
      expect(r.progress.last, 1.0);
    });

    test('fichier absent → exception explicite', () {
      expect(
        () => M3uParser.parseFile('${_tmp.path}/nope.m3u', [], [], [],
            accountId: 'a'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Encodage', () {
    test('Latin-1 : le fallback relit tout, sans doublon ni entrée perdue',
        () async {
      // Un fichier assez long pour que l'octet illégal en UTF-8 arrive APRÈS
      // plusieurs entrées déjà produites — c'est le cas que la lecture complète
      // ne pouvait pas rencontrer, et celui où un fallback naïf laisserait les
      // premières entrées en double.
      final b = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 500; i++) {
        b.writeln('#EXTINF:-1 group-title="Films",Film sans accent $i');
        b.writeln('http://srv.test/movie/u/p/$i.mp4');
      }
      b.writeln('#EXTINF:-1 group-title="Films",Cinéma Français');
      b.writeln('http://srv.test/movie/u/p/999.mp4');
      final f = _write('latin1.m3u', latin1.encode(b.toString()));

      final r = await _parse(f);

      expect(r.films.length, 501, reason: 'ni doublon ni perte après relecture');
      expect(r.films.last.title.baseTitle, 'Cinéma Français');
      expect(r.films.first.title.baseTitle, 'Film sans accent 0');
    });

    test('UTF-8 avec accents : pas de fallback déclenché à tort', () async {
      final f = _write('utf8.m3u',
          utf8.encode('#EXTM3U\n#EXTINF:-1 group-title="Films",Cinéma Français\n'
              'http://srv.test/movie/u/p/1.mp4\n'));
      final r = await _parse(f);
      expect(r.films.single.title.baseTitle, 'Cinéma Français');
    });
  });

  group('StringPool', () {
    test('les valeurs répétées partagent UNE instance', () async {
      // Les chaînes viennent d'un fichier : elles ne peuvent pas avoir été
      // canonicalisées à la compilation, contrairement à des littéraux.
      final f = _write('pool.m3u', utf8.encode(_buildM3u(200)));
      final r = await _parse(f);

      final a = r.films.first;
      final b = r.films.last;
      expect(a.groupTitle, b.groupTitle);
      expect(identical(a.groupTitle, b.groupTitle), isTrue,
          reason: '§ramDiet — `groupTitle` doit être mutualisé, pas recopié '
              'une fois par entrée');
      expect(identical(a.category, b.category), isTrue);
      expect(identical(a.title.quality, b.title.quality), isTrue);
      expect(identical(a.title.year, b.title.year), isTrue);
    });

    test('interner ne change AUCUNE valeur', () {
      final pool = StringPool();
      for (final s in ['FHD', '', 'Films | Action', 'é ù ç', '2020']) {
        final copy = String.fromCharCodes(s.codeUnits); // instance distincte
        expect(pool.of(copy), s);
      }
      expect(pool.of(null), isNull);
    });

    test('le pool inerte rend son argument tel quel', () {
      const pool = StringPool.none;
      final s = String.fromCharCodes('FHD'.codeUnits);
      expect(identical(pool.of(s), s), isTrue);
      expect(pool.distinct, 0);
    });

    test('passé le plafond, les valeurs restent correctes', () {
      final pool = StringPool();
      for (var i = 0; i < StringPool.maxDistinct + 50; i++) {
        expect(pool.of('v$i'), 'v$i');
      }
      expect(pool.distinct, StringPool.maxDistinct);
      // Ce qui était déjà mémorisé continue d'être partagé.
      expect(identical(pool.of('v0'), pool.of('v0')), isTrue);
    });

    test('ofList : liste vide partagée, éléments internés', () {
      final pool = StringPool();
      expect(identical(pool.ofList(const []), const <String>[]), isTrue);
      final a = pool.ofList([String.fromCharCodes('VF'.codeUnits)]);
      final b = pool.ofList([String.fromCharCodes('VF'.codeUnits)]);
      expect(a, ['VF']);
      expect(identical(a.first, b.first), isTrue);
    });
  });

  group('Désérialisation du cache', () {
    test('languages est une vraie liste, pas une vue sur le JSON brut', () {
      // §ramDiet — `.cast<String>()` renvoyait une vue qui retenait la
      // `List<dynamic>` sortie de `jsonDecode`, une par entrée.
      final json =
          jsonDecode('{"r":"T","b":"T","k":"t","l":["VF","VOSTFR"]}')
              as Map<String, dynamic>;
      final m = TitleMetadata.fromJson(json);
      expect(m.languages, ['VF', 'VOSTFR']);
      expect(m.languages, isNot(isA<List<dynamic>>().having(
          (l) => identical(l, json['l']), 'identique au JSON brut', isTrue)));
    });

    test('le pool mutualise entre deux entrées du même chargement', () {
      final pool = StringPool();
      Map<String, dynamic> row(String url) => jsonDecode(
            '{"u":"$url","t":0,"aid":"compte-1",'
            '"ti":{"r":"T","b":"T","k":"t","q":"FHD"},'
            '"g":"Films | Action","cat":"Action"}',
          ) as Map<String, dynamic>;

      final a = M3uEntry.fromJson(row('http://a'), pool);
      final b = M3uEntry.fromJson(row('http://b'), pool);

      expect(a.accountId, 'compte-1');
      expect(identical(a.accountId, b.accountId), isTrue);
      expect(identical(a.groupTitle, b.groupTitle), isTrue);
      expect(identical(a.category, b.category), isTrue);
      expect(identical(a.title.quality, b.title.quality), isTrue);
      // Les champs quasi uniques ne sont volontairement PAS internés.
      expect(a.url, isNot(b.url));
    });
  });
}
