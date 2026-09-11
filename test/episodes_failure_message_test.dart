import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/xtream_api_service.dart';
import 'package:aetherStream/feature/search/episodes_failure.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

/// Revue 2026-09-11, D4A-06 / D1A-07 — le motif d'échec des épisodes se
/// compose dans la langue de l'écran, jamais à partir du texte (français,
/// technique) du service.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  XtreamEpisodesResult ko(String error, LoadFailureKind kind) =>
      (episodes: null, error: error, kind: kind);
  XtreamEpisodesResult ok(List<M3uEntry> eps) =>
      (episodes: eps, error: null, kind: null);

  test('un seul compte qui répond suffit : pas de panne', () {
    expect(
        episodesFailureOf([
          ko('serveur injoignable', LoadFailureKind.network),
          ok(const []),
        ]),
        isNull);
    expect(episodesFailureOf(const []), isNull);
  });

  test('le premier échec l\'emporte, et la nature suit la LoadFailureKind', () {
    expect(
        episodesFailureOf([
          ko('trop de connexions', LoadFailureKind.busy),
          ko('serveur injoignable', LoadFailureKind.network),
        ]),
        EpisodesFailure.busy);
    expect(episodesFailureForKind(LoadFailureKind.parse), EpisodesFailure.parse);
    expect(episodesFailureForKind(LoadFailureKind.badAccount),
        EpisodesFailure.badAccount);
    expect(episodesFailureForKind(null), EpisodesFailure.network);
  });

  test('l\'échec constaté par la fiche prime sur la nature du service', () {
    expect(
        episodesFailureOf(
          [
            ko('identifiant de série illisible', LoadFailureKind.badAccount),
            ko('serveur injoignable', LoadFailureKind.network),
          ],
          local: const [EpisodesFailure.badSeriesId, null],
        ),
        EpisodesFailure.badSeriesId);
    expect(
        episodesFailureOf(
          [ko('compte introuvable', LoadFailureKind.badAccount)],
          local: const [EpisodesFailure.noAccount],
        ),
        EpisodesFailure.noAccount);
  });

  test('en anglais, la phrase entière est anglaise', () {
    for (final f in EpisodesFailure.values) {
      final sentence = en.detEpisodesError(episodesFailureText(en, f));
      expect(sentence, isNot(matches(RegExp(r'[àâéèêëîïôöùûüç]'))),
          reason: '$f : $sentence');
    }
    expect(en.detEpisodesError(episodesFailureText(en, EpisodesFailure.network)),
        'Episodes not loaded — the server is not responding.');
  });

  test('en français, chaque nature a son motif', () {
    final texts = {
      for (final f in EpisodesFailure.values) episodesFailureText(fr, f),
    };
    expect(texts.length, EpisodesFailure.values.length);
    expect(episodesFailureText(fr, EpisodesFailure.noAccount),
        'compte introuvable');
  });
}
