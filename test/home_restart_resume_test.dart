// R52 (2026-09-25) — « Lire depuis le début » (appui long sur une carte de
// l'accueil) n'efface que la reprise du MÊME élément.
//
// Le défaut : la tuile effaçait la reprise de toutes les `widget.versions` de
// la carte — pour un groupe de série, TOUS ses épisodes. Relancer S01E02
// depuis le début effaçait la reprise de S01E03.
//
// Sincérité : remettre `widget.versions` dans la boucle d'effacement de
// `home_card.dart` fait tomber le garde-fou du bas ; retirer le filtre
// saison/épisode de la règle fait tomber « S01E03 garde sa reprise ».

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/home/home_resume_actions.dart';

M3uEntry _episode(String account, int episode) => M3uEntry(
      url: 'http://$account.tv/series/u/p/${account}1$episode.mkv',
      accountId: account,
      type: M3uContentType.series,
      title: TitleMetadata(
        rawTitle: 'Dark S01E0$episode',
        baseTitle: 'Dark',
        seasonNumber: 1,
        episodeNumber: episode,
      ),
    );

M3uEntry _stub(String account) => M3uEntry(
      url: 'http://$account.tv/series/u/p/42',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
    );

M3uEntry _movie(String account, String quality) => M3uEntry(
      url: 'http://$account.tv/movie/u/p/$quality.mkv',
      accountId: account,
      type: M3uContentType.movie,
      title: TitleMetadata(
          rawTitle: 'Dune $quality', baseTitle: 'Dune', quality: quality),
    );

void main() {
  // Groupe MIXTE de l'accueil : le stub d'un compte Xtream, S01E02 sur deux
  // listes, S01E03 sur une.
  final M3uEntry stub = _stub('xtream');
  final M3uEntry e2vod = _episode('vod', 2);
  final M3uEntry e2test = _episode('testtv', 2);
  final M3uEntry e3vod = _episode('vod', 3);
  final List<M3uEntry> mixed = <M3uEntry>[stub, e2vod, e3vod, e2test];

  group('restartClearUrls — le MÊME élément, toutes ses versions', () {
    test('depuis S01E02 : ses deux versions, et S01E03 garde sa reprise', () {
      final List<String> urls = restartClearUrls(e2vod, mixed);
      expect(urls, containsAll(<String>[e2vod.url, e2test.url]));
      expect(urls, isNot(contains(e3vod.url)));
      expect(urls, isNot(contains(stub.url)),
          reason: 'la reprise portait sur un épisode : le repère de série reste');
      expect(urls, hasLength(2));
    });

    test('reprise portée par le stub : le stub s\'efface aussi, pas S01E03', () {
      final List<String> urls =
          restartClearUrls(e2vod, mixed, resumeOnStub: true);
      expect(urls, containsAll(<String>[e2vod.url, e2test.url, stub.url]));
      expect(urls, isNot(contains(e3vod.url)));
    });

    test('un film : toutes ses versions (§resumeUnify inchangé)', () {
      final M3uEntry hd = _movie('vod', 'HD');
      final M3uEntry uhd = _movie('testtv', '4K');
      expect(restartClearUrls(hd, <M3uEntry>[uhd, hd]),
          unorderedEquals(<String>[hd.url, uhd.url]));
    });

    test('aucun doublon, même si la cible est aussi dans le groupe', () {
      final List<String> urls =
          restartClearUrls(e2vod, <M3uEntry>[e2vod, e2vod, e2test]);
      expect(urls, hasLength(2));
    });
  });

  test('⛔ garde-fou : la tuile « depuis le début » de la carte passe par '
      'restartClearUrls, jamais par toutes les widget.versions', () {
    final String src =
        File('lib/feature/home/home_card.dart').readAsStringSync();
    final int start = src.indexOf('cardPlayFromStart');
    expect(start, greaterThan(0), reason: 'tuile « depuis le début » introuvable');
    final int end = src.indexOf('play(target:', start);
    expect(end, greaterThan(start));
    final String tile = src.substring(start, end);
    expect(tile, contains('restartClearUrls('));
    expect(tile, isNot(contains('in widget.versions')),
        reason: 'effacer toutes les versions du groupe = tous les épisodes');
  });
}
