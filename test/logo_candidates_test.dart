import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';

M3uEntry _entry({required String account, String? logo}) => M3uEntry(
      url: 'http://serveur/$account/${logo ?? "sans"}',
      type: M3uContentType.movie,
      title: TitleMetadata.parse('Un Film'),
      accountId: account,
      logoUrl: logo,
    );

void main() {
  group('§logoFallback — liste des adresses d\'image d\'un groupe', () {
    test('collecte toutes les adresses, sans les vides', () {
      final out = ParsedPlaylistService.logoCandidates([
        _entry(account: 'a', logo: 'http://a/img.jpg'),
        _entry(account: 'b'), // aucune adresse
        _entry(account: 'c', logo: ''), // adresse vide
        _entry(account: 'd', logo: 'http://d/img.jpg'),
      ]);
      expect(out, ['http://a/img.jpg', 'http://d/img.jpg']);
    });

    test('dédoublonne : deux listes peuvent servir la MÊME image', () {
      // Fréquent quand plusieurs fournisseurs pointent sur TMDB : essayer deux
      // fois la même adresse morte ne ferait que retarder le repli.
      final out = ParsedPlaylistService.logoCandidates([
        _entry(account: 'a', logo: 'http://image.tmdb.org/x.jpg'),
        _entry(account: 'b', logo: 'http://image.tmdb.org/x.jpg'),
      ]);
      expect(out, ['http://image.tmdb.org/x.jpg']);
    });

    test('un groupe sans aucune adresse renvoie une liste vide', () {
      // C'est ce cas qui déclenche le repli TMDB immédiat côté carte : il ne
      // faut donc surtout pas renvoyer une chaîne vide, qui serait « essayée ».
      final out = ParsedPlaylistService.logoCandidates([
        _entry(account: 'a'),
        _entry(account: 'b', logo: ''),
      ]);
      expect(out, isEmpty);
    });

    test('groupe vide → liste vide, jamais d\'exception', () {
      expect(ParsedPlaylistService.logoCandidates(const []), isEmpty);
    });

    test('une seule version : son adresse, sans passer par le tri', () {
      final out = ParsedPlaylistService.logoCandidates([
        _entry(account: 'a', logo: 'http://a/img.jpg'),
      ]);
      expect(out, ['http://a/img.jpg']);
    });
  });
}
