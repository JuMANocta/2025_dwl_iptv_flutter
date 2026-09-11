import 'package:aetherStream/feature/replay/replay_day_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D2A-19 — « Hier » était faux le 1er du mois, alors que
/// c'est le jour sélectionné par défaut du sélecteur de replay.
void main() {
  test('jour ordinaire : aujourd’hui, hier, avant-hier', () {
    final now = DateTime(2026, 9, 11, 14, 30);
    expect(replayDayLabelKind(DateTime(2026, 9, 11), now),
        ReplayDayLabelKind.today);
    expect(replayDayLabelKind(DateTime(2026, 9, 10), now),
        ReplayDayLabelKind.yesterday);
    expect(replayDayLabelKind(DateTime(2026, 9, 9), now),
        ReplayDayLabelKind.other);
  });

  test('le 1er mars : le 28 février est « Hier »', () {
    final now = DateTime(2027, 3, 1, 10);
    expect(replayDayLabelKind(DateTime(2027, 2, 28), now),
        ReplayDayLabelKind.yesterday);
    expect(replayDayLabelKind(DateTime(2027, 3, 1), now),
        ReplayDayLabelKind.today);
  });

  test('le 1er mars d’une année bissextile : le 29 février est « Hier »', () {
    final now = DateTime(2028, 3, 1, 8);
    expect(replayDayLabelKind(DateTime(2028, 2, 29), now),
        ReplayDayLabelKind.yesterday);
    expect(replayDayLabelKind(DateTime(2028, 2, 28), now),
        ReplayDayLabelKind.other);
  });

  test('le 1er janvier : le 31 décembre de l’année PRÉCÉDENTE est « Hier »',
      () {
    final now = DateTime(2027, 1, 1, 0, 5);
    expect(replayDayLabelKind(DateTime(2026, 12, 31), now),
        ReplayDayLabelKind.yesterday);
  });

  test('« Aujourd’hui » tient compte de l’année', () {
    final now = DateTime(2027, 9, 11);
    expect(replayDayLabelKind(DateTime(2026, 9, 11), now),
        ReplayDayLabelKind.other);
    expect(replayDayLabelKind(DateTime(2026, 9, 10), now),
        ReplayDayLabelKind.other);
  });

  test('l’heure du jour comparé ne compte pas (seule la date)', () {
    final now = DateTime(2026, 3, 30, 9);
    // Lendemain du passage à l'heure d'été en Europe : la veille reste le 29.
    expect(replayDayLabelKind(DateTime(2026, 3, 29, 23, 59), now),
        ReplayDayLabelKind.yesterday);
    expect(replayDayLabelKind(DateTime(2026, 3, 28, 23), now),
        ReplayDayLabelKind.other);
  });
}
