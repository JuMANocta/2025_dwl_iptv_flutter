/// Lot 7 — Les jours proposés par le replay, calculés une seule fois et
/// testables sans écran.
///
/// ⛔ **Le piège que ce fichier existe pour fermer** : un jour de calendrier ne
/// se retire pas avec une DURÉE. `DateTime(2026, 3, 29).subtract(const
/// Duration(days: 1))` ne rend PAS le 28 à minuit en France : la nuit du
/// passage à l'heure d'été ne dure que 23 heures, et on obtient le 28 à 01:00.
/// Le picker comparait ensuite ce `DateTime` à des minuits locaux
/// (`XmltvService.getAvailableDays` en produit, `getProgramsForDay` compare
/// année/mois/jour) : la pastille « guide disponible » s'éteignait et la grille
/// du jour se vidait, deux fois par an, sur toute la fenêtre de replay.
///
/// La règle du projet est explicite : **veille = `DateTime(y, m, j - 1)`**, et
/// jamais `subtract(Duration(days: 1))`. Le constructeur de `DateTime`
/// normalise les valeurs hors bornes (jour 0 → dernier jour du mois précédent,
/// jour -3 → l'avant-avant-veille de ce dernier), donc un simple `j - i` suffit
/// et reste juste aux changements de mois, d'année et de bissextile.
library;

/// Minuit local du jour de [t], sans arithmétique de durée.
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Minuit local du jour situé [daysBack] jours avant [t].
///
/// [daysBack] peut dépasser la longueur du mois : `DateTime` normalise.
DateTime dayBefore(DateTime t, int daysBack) =>
    DateTime(t.year, t.month, t.day - daysBack);

/// Les mêmes jour, mois et année — la seule comparaison qui a un sens entre
/// deux dates de calendrier.
///
/// ⚠️ Comparer deux `DateTime` par `==` compare des INSTANTS : deux valeurs qui
/// désignent le même jour mais pas la même heure sont différentes, et c'est
/// exactement ce qui faisait rater la pastille EPG.
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Les jours offerts par le sélecteur, du plus récent au plus ancien :
/// aujourd'hui, hier, … jusqu'à [maxDays] jours au total.
///
/// [maxDays] vient de `catchupDays` du fournisseur ; une valeur ≤ 0 ne donne
/// aucun jour (le picker manuel reste, lui, toujours affiché).
List<DateTime> replayDays(DateTime now, int maxDays) => <DateTime>[
      for (int i = 0; i < maxDays; i++) dayBefore(now, i),
    ];

/// Le jour proposé à l'ouverture : **la veille**.
///
/// C'est le seul jour dont on est sûr qu'il est entièrement passé — donc
/// entièrement disponible en replay, de la première à la dernière minute.
DateTime replayDefaultDay(DateTime now) => dayBefore(now, 1);
