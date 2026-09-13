// R38 (2026-09-13) — **L'appui long sur une SÉRIE proposait « Lire », et jouait
// une URL qui n'est pas un flux.**
//
// Le catalogue Xtream ne contient qu'UNE entrée par série : son stub
// `/series/{user}/{pass}/{series_id}`, dont le parseur dit lui-même que ce
// n'est « PAS un endpoint de stream » (`xtream_catalog_parser`). Le tap simple
// gardait déjà la série pour la fiche ; la feuille d'appui long, elle, n'avait
// aucune garde de type et poussait `PlayerPage(path: entry.url)` avec ce stub.
// §heroSeriesResume (la veille) l'a rendu visible : la progression d'un épisode
// s'écrivant désormais aussi sous le stub, la tuile se mettait à proposer
// « Reprendre · mm:ss » sur un chemin injouable.
//
// ⚠️ Ce qui se teste ici est la GARDE, pas la feuille : monter `_HomeCard`
// demanderait TMDB, les préférences et un `MediaStore`. Les règles sont pures
// et ce sont elles qui décident des tuiles.
//
// ⚠️ Les deux pièges que ces règles doivent éviter :
//   1. une série n'est pas reconnaissable à son TYPE — une liste M3U porte ses
//      épisodes comme autant d'entrées `series` à l'URL bien réelle
//      (§Ultimate), et leur appui long doit continuer de lire ;
//   2. la question se pose sur le GROUPE — un titre peut mélanger le stub d'un
//      compte Xtream et les épisodes M3U d'un autre (§seriesMultiList).

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/home/home_page.dart';

/// Le stub tel que `xtream_catalog_parser` en produit un par série et par
/// compte : type `series`, aucune numérotation, dernier segment entier nu.
M3uEntry _stub({String account = 'a', String id = '42'}) => M3uEntry(
      url: 'http://$account.tv/series/user/pass/$id',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
    );

/// Un épisode numéroté dont l'URL n'a **pas** d'extension.
///
/// ⚠️ C'est la seule forme SINCÈRE pour éprouver le court-circuit sur le titre :
/// avec un `.mkv`, le test d'extension rejetait déjà l'entrée et le cas passait
/// au vert même en retirant le court-circuit — le test annonçait tenir une
/// règle qu'il ne touchait pas.
M3uEntry _episodeSansExtension({String account = 'a'}) => M3uEntry(
      url: 'http://$account.tv/series/user/pass/9002',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(
        rawTitle: 'Dark S01E02',
        baseTitle: 'Dark',
        seasonNumber: 1,
        episodeNumber: 2,
      ),
    );

/// Un épisode de liste M3U tel qu'on en voit vraiment : numéroté ET avec
/// extension.
M3uEntry _episodeM3u({String account = 'm3u'}) => M3uEntry(
      url: 'http://$account.tv/series/user/pass/9002.mkv',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(
        rawTitle: 'Dark S01E02',
        baseTitle: 'Dark',
        seasonNumber: 1,
        episodeNumber: 2,
      ),
    );

void main() {
  group('isSeriesStubEntry — ce qui NE se lit PAS', () {
    test('le stub du catalogue Xtream est reconnu', () {
      expect(isSeriesStubEntry(_stub()), isTrue);
    });

    test('le préfixe /series/ est reconnu quelle que soit sa casse', () {
      final entry = M3uEntry(
        url: 'http://a.tv/Series/user/pass/42',
        accountId: 'a',
        type: M3uContentType.series,
        title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
      );

      expect(isSeriesStubEntry(entry), isTrue);
    });
  });

  group('isSeriesStubEntry — ce qui se lit toujours', () {
    test('⚠️ un épisode numéroté SANS extension garde sa lecture directe', () {
      // Le seul cas où le court-circuit sur le titre décide seul : l'URL a la
      // forme exacte d'un stub (segments `series/…`, dernier segment entier nu)
      // et c'est la numérotation du titre qui dit que c'en est un vrai épisode.
      expect(isSeriesStubEntry(_episodeSansExtension()), isFalse);
    });

    test('un épisode M3U numéroté avec extension garde sa lecture', () {
      expect(isSeriesStubEntry(_episodeM3u()), isFalse);
    });

    test('une entrée /series/ avec extension est un épisode, pas un stub', () {
      // Même sans SxxExx dans le titre : l'extension dit que c'est un fichier.
      final entry = M3uEntry(
        url: 'http://a.tv/series/user/pass/9002.mp4',
        accountId: 'a',
        type: M3uContentType.series,
        title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
      );

      expect(isSeriesStubEntry(entry), isFalse);
    });

    test('un film ne passe jamais par la garde', () {
      final film = M3uEntry(
        url: 'http://a.tv/movie/user/pass/7.mkv',
        accountId: 'a',
        type: M3uContentType.movie,
        title: const TitleMetadata(rawTitle: 'Heat', baseTitle: 'Heat'),
      );

      expect(isSeriesStubEntry(film), isFalse);
    });

    test('une chaîne ne passe jamais par la garde', () {
      final chaine = M3uEntry(
        url: 'http://a.tv/live/user/pass/1.ts',
        accountId: 'a',
        type: M3uContentType.tv,
        title: const TitleMetadata(rawTitle: 'TF1', baseTitle: 'TF1'),
      );

      expect(isSeriesStubEntry(chaine), isFalse);
    });
  });

  group('isSeriesStubEntry — les formes qu\'on ne reconnaît pas', () {
    test('dernier segment non entier : ce n\'est pas un stub d\'API', () {
      // Même règle que `DetailsPage._extractSeriesIdFromUrl` : sans series_id
      // entier, la fiche ne saurait pas non plus fetcher les épisodes.
      final entry = M3uEntry(
        url: 'http://a.tv/series/user/pass/dark',
        accountId: 'a',
        type: M3uContentType.series,
        title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
      );

      expect(isSeriesStubEntry(entry), isFalse);
    });

    test('URL trop courte ou vide : rien à décider, on ne bloque pas', () {
      for (final url in <String>['', 'http://a.tv/series/42', ':: pas une url']) {
        final entry = M3uEntry(
          url: url,
          accountId: 'a',
          type: M3uContentType.series,
          title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
        );

        expect(isSeriesStubEntry(entry), isFalse, reason: 'URL « $url »');
      }
    });
  });

  // R38 — La garde porte sur le GROUPE. Interroger `versions.first` laissait le
  // défaut d'origine intact dès qu'un épisode M3U se trouvait en tête : « Lire »
  // jouait un épisode arbitraire sous le nom de la série.
  group('groupHasSeriesStub — la décision se prend sur tout le groupe', () {
    test('⚠️ groupe MIXTE, épisode M3U en tête : reconnu comme série', () {
      // Le cas que personne ne testait et que personne ne voyait : le stub est
      // là, mais il n'est pas premier.
      final versions = <M3uEntry>[
        _episodeM3u(),
        _episodeM3u(account: 'm3u2'),
        _stub(account: 'xtream'),
      ];

      expect(groupHasSeriesStub(versions), isTrue);
    });

    test('groupe de stubs seuls (plusieurs comptes Xtream) : reconnu', () {
      expect(
        groupHasSeriesStub([_stub(account: 'a'), _stub(account: 'b')]),
        isTrue,
      );
    });

    test('groupe d\'épisodes M3U seuls : la lecture directe reste', () {
      expect(
        groupHasSeriesStub([_episodeM3u(), _episodeM3u(account: 'm3u2')]),
        isFalse,
      );
    });

    test('groupe vide : rien à bloquer', () {
      expect(groupHasSeriesStub(const <M3uEntry>[]), isFalse);
    });
  });
}
