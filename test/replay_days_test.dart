// Lot 7 — Les jours du replay.
//
// Ce que ces tests tiennent : qu'un jour de calendrier se retire en JOURS et
// jamais en `Duration`. Le picker utilisait `subtract(const Duration(days: 1))`
// à deux endroits (jour par défaut, et la liste entière des onglets) ; deux
// fois par an, la nuit d'un changement d'heure ne dure pas 24 h et le résultat
// n'est plus minuit — la grille du jour se vidait et la pastille « guide
// disponible » s'éteignait sur toute la fenêtre de replay.
//
// ⚠️ **Sincérité et fuseau.** Un test qui dépendrait du fuseau de la machine
// mentirait sur le CI (UTC, sans heure d'été). Les tests ci-dessous vérifient
// donc ce qui est vrai PARTOUT : la date de calendrier obtenue, jamais l'heure.
// Le cas « heure d'été » est éprouvé par la propriété qui l'attrape :
// `dayBefore` rend toujours MINUIT, quoi qu'il arrive à la durée du jour —
// `subtract(Duration(days: 1))`, lui, ne le garantit pas.
//
// Mutation : remplacer `DateTime(t.year, t.month, t.day - n)` par
// `startOfDay(t).subtract(Duration(days: n))` laisse passer les tests de date
// sur une machine en UTC, mais fait tomber « minuit, toujours » dès qu'un
// fuseau à heure d'été est utilisé — c'est pour ça que les deux familles de
// tests sont là.

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/replay/replay_days.dart';

void main() {
  group('dayBefore — la veille est une date, pas une soustraction', () {
    test('un jour ordinaire', () {
      expect(dayBefore(DateTime(2026, 9, 17, 22, 41), 1), DateTime(2026, 9, 16));
    });

    test('le 1er du mois remonte au mois précédent', () {
      expect(dayBefore(DateTime(2026, 9, 1, 0, 5), 1), DateTime(2026, 8, 31));
    });

    test('le 1er janvier remonte à l\'année précédente', () {
      expect(dayBefore(DateTime(2026, 1, 1, 12), 1), DateTime(2025, 12, 31));
    });

    test('février bissextile : le 1er mars 2024 remonte au 29', () {
      expect(dayBefore(DateTime(2024, 3, 1), 1), DateTime(2024, 2, 29));
    });

    test('février NON bissextile : le 1er mars 2026 remonte au 28', () {
      expect(dayBefore(DateTime(2026, 3, 1), 1), DateTime(2026, 2, 28));
    });

    test('un recul plus long que le mois se normalise', () {
      expect(dayBefore(DateTime(2026, 3, 5), 10), DateTime(2026, 2, 23));
      expect(dayBefore(DateTime(2026, 1, 3), 14), DateTime(2025, 12, 20));
    });

    test('⚠️ le résultat est TOUJOURS minuit — c\'est tout le sujet', () {
      // La nuit du 29 mars 2026 en Europe ne dure que 23 h. Une soustraction
      // de 24 h depuis le 29 à minuit ne tombe pas sur le 28 à minuit ; un
      // calcul en jours, si.
      for (final DateTime t in <DateTime>[
        DateTime(2026, 3, 29, 14, 30),
        DateTime(2026, 10, 25, 14, 30),
        DateTime(2026, 3, 30),
        DateTime(2026, 10, 26),
      ]) {
        for (int i = 0; i < 15; i++) {
          final DateTime d = dayBefore(t, i);
          expect(d.hour, 0, reason: '$t − $i jours');
          expect(d.minute, 0, reason: '$t − $i jours');
          expect(d.second, 0, reason: '$t − $i jours');
        }
      }
    });
  });

  group('replayDays — les onglets du sélecteur', () {
    test('rend maxDays jours, du plus récent au plus ancien', () {
      final days = replayDays(DateTime(2026, 9, 17, 9), 7);
      expect(days.length, 7);
      expect(days.first, DateTime(2026, 9, 17));
      expect(days.last, DateTime(2026, 9, 11));
    });

    test('chaque jour est exactement le précédent, sans trou ni doublon', () {
      final days = replayDays(DateTime(2026, 3, 3, 23, 59), 14);
      for (int i = 1; i < days.length; i++) {
        expect(
          days[i],
          dayBefore(days[i - 1], 1),
          reason: 'entre l\'onglet ${i - 1} et l\'onglet $i',
        );
      }
      expect(days.toSet().length, days.length, reason: 'aucun doublon');
    });

    test('une fenêtre nulle ou négative ne propose aucun jour', () {
      expect(replayDays(DateTime(2026, 9, 17), 0), isEmpty);
      expect(replayDays(DateTime(2026, 9, 17), -3), isEmpty);
    });
  });

  group('replayDefaultDay — la veille, et pourquoi', () {
    test('c\'est le seul jour entièrement passé, donc entièrement dispo', () {
      expect(replayDefaultDay(DateTime(2026, 9, 17, 0, 1)), DateTime(2026, 9, 16));
      expect(replayDefaultDay(DateTime(2026, 9, 17, 23, 59)), DateTime(2026, 9, 16));
    });

    test('c\'est le deuxième onglet de la liste', () {
      final now = DateTime(2026, 5, 1, 8);
      expect(replayDefaultDay(now), replayDays(now, 7)[1]);
    });
  });

  group('isSameCalendarDay — comparer des jours, pas des instants', () {
    test('même jour à des heures différentes', () {
      expect(
        isSameCalendarDay(DateTime(2026, 9, 17), DateTime(2026, 9, 17, 23, 59)),
        isTrue,
      );
    });

    test('⚠️ là où `==` se trompait : minuit contre 01:00 le même jour', () {
      final a = DateTime(2026, 3, 28);
      final b = DateTime(2026, 3, 28, 1);
      expect(a == b, isFalse, reason: '`==` compare des instants');
      expect(isSameCalendarDay(a, b), isTrue, reason: 'et nous, des jours');
    });

    test('deux jours voisins ne se confondent pas', () {
      expect(
        isSameCalendarDay(DateTime(2026, 9, 17), DateTime(2026, 9, 18)),
        isFalse,
      );
    });

    test('même quantième, mois ou année différents', () {
      expect(
        isSameCalendarDay(DateTime(2026, 9, 17), DateTime(2026, 8, 17)),
        isFalse,
      );
      expect(
        isSameCalendarDay(DateTime(2026, 9, 17), DateTime(2025, 9, 17)),
        isFalse,
      );
    });
  });
}
