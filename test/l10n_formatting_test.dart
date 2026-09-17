import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playback_health_service.dart';
import 'package:aetherStream/feature/player/player_media.dart';
import 'package:aetherStream/feature/player/player_page.dart'
    show PlayerBadgeType, VideoSourceType;
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// Revue 2026-09-11, lot 7 — Des textes composés AILLEURS que dans un widget
/// (service, modèle, fonction pure) qui s'affichaient en français quelle que
/// soit la langue de l'appareil. Chaque test vérifie la version anglaise ET
/// que le français affiché reste celui d'avant.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));
  final RegExp frenchMark = RegExp(r'[àâéèêëîïôöùûüç]');

  tearDown(L10n.resetForTest);

  group('D1B-07 — bilan de santé de lecture (carte de compte)', () {
    const h = AccountPlaybackHealth(
        sessions: 2, stalls: 3, watched: Duration(hours: 2, minutes: 10));

    test('en anglais, rien de français', () {
      expect(h.displaySummary(en), '3 stalls · 1.4/h · 2h 10m watched');
    });

    test('en français, le texte de l\'écran reste celui d\'avant', () {
      expect(h.displaySummary(fr), '3 blocages · 1,4/h · 2h10 vues');
    });

    test('un vrai pluriel, et « aucun » plutôt que « 0 »', () {
      const one = AccountPlaybackHealth(
          sessions: 1, stalls: 1, watched: Duration(minutes: 2));
      expect(one.displaySummary(en), '1 stall · 2 min watched');
      const none = AccountPlaybackHealth(
          sessions: 1, stalls: 0, watched: Duration(minutes: 2));
      expect(none.displaySummary(fr), 'aucun blocage · 2 min vues');
    });

    test('le résumé du JOURNAL, lui, ne change pas', () {
      expect(h.summary, '3 blocages · 1.4/h · 2h10 vues');
    });
  });

  group('D1B-19 — tailles et durées', () {
    test('taille de fichier : unité et séparateur de la langue', () {
      const int gib = 1024 * 1024 * 1024;
      expect(formatFileSize(gib + gib ~/ 2, en), '1.50 GB');
      expect(formatFileSize(gib + gib ~/ 2, fr), '1,50 Go');
    });

    // R8 (2026-09-16) — UN seul formateur de tailles, et une précision qui se
    // lit. ⚠️ « 512.00 kB » et « 0 octets » étaient les sorties d'avant :
    // deux décimales inutiles sur des kilooctets, et un pluriel sur zéro.
    test("R8 — la précision suit l'unité", () {
      const int kib = 1024;
      expect(formatFileSize(512 * kib, en), '512 kB');
      expect(formatFileSize(300 * kib, fr), '300 Ko');
      // ⚠️ Le cas qui a fait naître la règle : 300 Ko arrondis au mégaoctet
      // donneraient « 0,0 Mo », c'est-à-dire « rien à récupérer ».
      expect(formatFileSize(300 * kib, fr), isNot(contains('Mo')));
      expect(formatFileSize(217 * kib * kib, fr), '217,0 Mo');
      expect(formatFileSize((12.3 * kib * kib).round(), fr), '12,3 Mo');
      expect(formatFileSize((12.3 * kib * kib).round(), en), '12.3 MB');
    });

    test('R8 — « 0 octet » au singulier, « 2 octets » au pluriel', () {
      expect(formatFileSize(0, fr), '0 octet');
      expect(formatFileSize(1, fr), '1 octet');
      expect(formatFileSize(2, fr), '2 octets');
      expect(formatFileSize(0, en), '0 B');
    });

    test('durées courtes', () {
      expect(formatShortDuration(const Duration(minutes: 45), en), '45 min');
      expect(formatShortDuration(const Duration(hours: 1, minutes: 5), fr),
          '1h05');
      expect(formatShortDelay(const Duration(minutes: 3), en), '3 min');
      expect(formatShortDelay(const Duration(seconds: 25), en), '25 s');
    });
  });

  test('D1A-07 — le détail d\'un échec de liste est traduit', () {
    L10n.bind(en);
    final String text = describeFailure(LoadFailure(
      LoadFailureKind.deferred,
      detail: L10n.current
          .failDetailTooLong(formatShortDelay(const Duration(minutes: 3))),
      at: DateTime(2026, 9, 11),
    ));
    // R8 (2026-09-16) — Le motif ne dit plus « après le démarrage » : ce n'est
    // vrai que d'UN des trois endroits qui reportent une liste. Les deux
    // autres (le chargement de la flotte, 4 s après le boot, et son délai
    // dépassé) reportent alors que le démarrage est fini depuis longtemps.
    expect(text,
        'Update postponed: this list will be picked up. (still not ready after 3 min)');
    expect(
        describeFailure(LoadFailure(LoadFailureKind.cacheGone,
            detail: L10n.current.failDetailCacheCleared,
            at: DateTime(2026, 9, 11))),
        isNot(matches(frenchMark)));
  });

  test('D1A-08 — compteur de l\'écran de démarrage', () {
    expect(en.bootDetailEntries(1, '1'), '1 entry');
    expect(en.bootDetailEntries(300, '300'), '300 entries');
    expect(fr.bootDetailEntries(300, '300'), '300 entrées');
    expect(en.bootDetailSection(en.bootSectionMovies, '24 100', '53 781'),
        'movies · 24 100/53 781');
  });

  test('D1A-09 — une erreur de PlaylistService se lit dans la langue de '
      'l\'écran, et describeError la rend telle quelle', () {
    L10n.bind(en);
    final String msg =
        describeError(HttpException(L10n.current.playlistInvalidUrl('Box')));
    expect(msg, en.playlistInvalidUrl('Box'));
    expect(msg, isNot(matches(frenchMark)));
    expect(describeError(HttpException(L10n.current.playlistNoActiveAccount)),
        en.playlistNoActiveAccount);
  });

  test('D1A-10 — durée TMDB composée à l\'affichage', () {
    Media m({int? minutes, bool perEpisode = false}) => Media(
          id: 1,
          title: 'X',
          overview: '',
          voteAverage: 0,
          genres: const [],
          cast: const [],
          runtimeMinutes: minutes,
          runtimePerEpisode: perEpisode,
        );
    expect(m(minutes: 135).runtimeLabel(en), '2h 15m');
    expect(m(minutes: 135).runtimeLabel(fr), '2 h 15 min');
    expect(m(minutes: 45, perEpisode: true).runtimeLabel(en), '45m/episode');
    expect(m(minutes: 45, perEpisode: true).runtimeLabel(fr), '45m/épisode');
    expect(m().runtimeLabel(en), isNull);
    expect(m(minutes: 0, perEpisode: true).runtimeLabel(en), isNull);
  });

  test('D2A-08 — la notification d\'une chaîne parle anglais en anglais', () {
    L10n.bind(en);
    final n = nowPlayingFor(const PlayerMedia(
      path: 'http://x/y.ts',
      title: 'TF1',
      badgeType: PlayerBadgeType.live,
      sourceType: VideoSourceType.network,
    ));
    expect(n.subtitle, 'Live');
  });

  test('D3A-11 — moyenne de la notification de téléchargement', () {
    expect(en.dlNoticeAverage(27), '27% on average');
    expect(fr.dlNoticeAverage(27), '27 % en moyenne');
  });

  test('D4B-17 — les pseudo-pluriels « (s) » sont de vrais pluriels', () {
    expect(en.perfPurgeDone('1 MB', 1), '🧹 1 MB freed (1 file)');
    expect(en.perfPurgeDone('3 MB', 4), '🧹 3 MB freed (4 files)');
    expect(fr.termPreviousErrors(2), '2 ERREURS PRÉCÉDENTES');
    expect(fr.termPreviousErrors(1), '1 ERREUR PRÉCÉDENTE');
    expect(en.perfFreeMemoryDone(2),
        '💤 2 secondary accounts unloaded from memory');
    for (final l in [en, fr]) {
      expect(l.perfStorageReclaimable('1 MB', 3), isNot(contains('(s)')));
    }
  });

  // Revue 2026-09-11, lot 7 — trouvé à la RELECTURE du lot.
  group('relecture', () {
    test('nombres groupés dans la langue de l\'écran (votes, démarrage)', () {
      // Le groupement « 12 400 » (espace) d'un écran anglais se lisait comme
      // une traduction oubliée ; le français ne bouge pas d'un caractère.
      expect(en.detVotes(12400, formatCountFor(12400, en)), '12,400 votes');
      expect(fr.detVotes(12400, formatCountFor(12400, fr)), '12 400 votes');
      expect(en.detVotes(1, formatCountFor(1, en)), '1 vote');
      expect(formatCountFor(153062, fr), formatCount(153062));
      expect(en.bootDetailEntries(153062, formatCountFor(153062, en)),
          '153,062 entries');
    });

    test('un film de moins d\'une heure : « 45 min », plus « 0h 45m »', () {
      final m = Media(
        id: 1,
        title: 'X',
        overview: '',
        voteAverage: 0,
        genres: const [],
        cast: const [],
        runtimeMinutes: 45,
      );
      expect(m.runtimeLabel(en), '45 min');
      expect(m.runtimeLabel(fr), '45 min');
    });

    test('durée longue : notation anglaise en anglais, française inchangée', () {
      const d = Duration(hours: 1, minutes: 5);
      expect(formatShortDuration(d, en), '1h 05m');
      expect(formatShortDuration(d, fr), '1h05');
    });

    test('§clientText — ni « yet » ni « pas encore » sur le guide vide', () {
      expect(en.xmltvNoGuide, isNot(contains('yet')));
      expect(fr.xmltvNoGuide, isNot(contains('encore')));
    });

    test('D1A-07 — une liste à ré-analyser n\'affiche plus de jargon '
        'français sous sa puce', () {
      L10n.bind(en);
      const String id = 'relecture-lot7-markStale';
      ParsedPlaylistService.markStale(id);
      final LoadFailure? f = ParsedPlaylistService.failureOf(id);
      expect(f, isNotNull);
      expect(f!.detail, isNull);
      expect(describeFailure(f), isNot(matches(frenchMark)));
    });
  });
}
