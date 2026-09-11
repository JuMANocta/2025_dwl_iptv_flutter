import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/downloads/logic/download_naming.dart';

/// Revue 2026-09-11 (D3A-04, D3A-10) — Le nom du fichier téléchargé.
///
/// Avant : l'extension se lisait sur le DERNIER POINT, du nom comme de l'URL.
/// « Mr. Robot S01 E01 » était écrit sans extension (chemin rapide perdu,
/// repli MediaStore bloqué) et une URL nue mettait l'hôte et les identifiants
/// dans le « type de fichier ».
void main() {
  group('urlFileExtension', () {
    test('lit l\'extension du DERNIER segment du chemin', () {
      expect(urlFileExtension('http://h:8080/movie/u/p/123.mkv'), 'mkv');
      expect(urlFileExtension('http://h/series/u/p/9.MP4'), 'mp4');
    });

    test('ignore la requête', () {
      expect(urlFileExtension('http://h/movie/u/p/1.mkv?token=x.y'), 'mkv');
    });

    test('🔴 URL sans extension : null, jamais l\'hôte ni les identifiants', () {
      expect(urlFileExtension('http://1.2.3.4:8080/movie/jean/s3cr3t/123'),
          isNull);
    });

    test('extension implausible : null', () {
      expect(urlFileExtension('http://h/a/b.verylongext'), isNull);
      expect(urlFileExtension('http://h/a/b.'), isNull);
      expect(urlFileExtension('http://h/'), isNull);
      expect(urlFileExtension('http://h/.hidden'), isNull);
    });
  });

  group('downloadFileName', () {
    test('🔴 un point dans le titre n\'empêche plus l\'extension', () {
      expect(
        downloadFileName(
            name: 'Mr. Robot S01 E01', url: 'http://h/series/u/p/123.mkv'),
        'Mr. Robot S01 E01.mkv',
      );
    });

    test('🔴 un point + une année : l\'extension est posée après l\'année', () {
      expect(
        downloadFileName(
          name: 'Guardians of the Galaxy Vol. 2',
          year: '2017',
          url: 'http://h/movie/u/p/7.mkv',
        ),
        'Guardians of the Galaxy Vol. 2 (2017).mkv',
      );
    });

    test('🔴 URL nue : mp4, et rien de l\'URL dans le nom', () {
      final String n = downloadFileName(
          name: 'Heat', url: 'http://1.2.3.4:8080/movie/jean/s3cr3t/123');
      expect(n, 'Heat.mp4');
      expect(n, isNot(contains('jean')));
      expect(n, isNot(contains('/')));
    });

    test('le nom qui porte déjà l\'extension ne la reçoit pas deux fois', () {
      expect(downloadFileName(name: 'film.mkv', url: 'http://h/1.mkv'),
          'film.mkv');
      expect(downloadFileName(name: 'film.MKV', url: 'http://h/1.mkv'),
          'film.MKV');
    });

    test('cas simple inchangé', () {
      expect(downloadFileName(name: 'Heat', year: '1995', url: 'http://h/1.mp4'),
          'Heat (1995).mp4');
      expect(downloadFileName(name: 'Heat', year: '', url: 'http://h/1.avi'),
          'Heat.avi');
    });

    test('caractères interdits assainis, # et % compris (D3A-10)', () {
      expect(
        downloadFileName(name: '#Alive 100% Wolf: 2/3', url: 'http://h/1.mkv'),
        '_Alive 100_ Wolf_ 2_3.mkv',
      );
    });
  });
}
