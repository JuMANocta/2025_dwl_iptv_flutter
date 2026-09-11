/// Libellé d'un jour du sélecteur de replay (revue 2026-09-11, D2A-19).
///
/// ⚠️ L'ancien test comparait les JOURS DU MOIS
/// (`d.day == today.day - 1 && d.month == today.month`) : le 1er de chaque
/// mois, la veille (le 31 ou le 30 du mois précédent) — qui est aussi la puce
/// sélectionnée PAR DÉFAUT — s'affichait « dim. 31 » au lieu de « Hier ».
/// Et « Aujourd'hui » ignorait l'année.
///
/// On compare donc des DATES CALENDAIRES complètes (année, mois, jour), la
/// veille étant calculée par `DateTime(y, m, j - 1)` — qui normalise le
/// changement de mois et d'année — et non par `subtract(Duration(days: 1))`,
/// qui retire 24 h et tombe la veille à 23 h le lendemain d'un passage à
/// l'heure d'été. Pur : testé par `replay_day_label_test.dart`.
library;

enum ReplayDayLabelKind { today, yesterday, other }

ReplayDayLabelKind replayDayLabelKind(DateTime day, DateTime now) {
  if (_sameDate(day, now)) return ReplayDayLabelKind.today;
  final DateTime yesterday = DateTime(now.year, now.month, now.day - 1);
  if (_sameDate(day, yesterday)) return ReplayDayLabelKind.yesterday;
  return ReplayDayLabelKind.other;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
