import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';

/// Taille d'un fichier, dans la langue de l'écran. **Le seul formateur de
/// tailles de l'app.**
///
/// Revue 2026-09-11, D1B-19 — Écrivait « B / KB / MB / GB » en dur, avec un
/// point décimal : en français, la tuile de téléchargement affichait
/// « 1.50 GB » pendant que l'Optimisation disait « 12.3 Mo ». Les unités
/// passent désormais par les clés `size*`, et le séparateur décimal suit la
/// langue (« 1,50 Go »).
///
/// R8 (2026-09-16) — ⚠️ Il en restait DEUX : `StorageJanitor.humanBytes`
/// écrivait sa propre arithmétique avec `toStringAsFixed`, dont le séparateur
/// est **toujours** le point, quelle que soit la langue — « 12.3 Mo » sur la
/// page Optimisation contre « 1,50 Go » sur une tuile de téléchargement, dans
/// la même application et parfois sur le même écran. `humanBytes` délègue
/// désormais ici ; ⛔ ne pas recréer un second formateur « juste pour cet
/// écran-là ».
///
/// La précision suit l'unité, comme le faisait `humanBytes` : un chiffre rond
/// se lit, « 512,00 ko » et « 0,0 Mo » non.
///   - sous le kilooctet : des octets entiers, au singulier quand il le faut
///     (« 0 octet », et non « 0 octets ») ;
///   - sous le mégaoctet : des kilooctets entiers (« 300 ko ») — ⚠️ un cache
///     de 300 Ko affiché « 0,0 Mo » disait « il n'y a rien à récupérer » ;
///   - sous le gigaoctet : une décimale (« 12,3 Mo ») ;
///   - au-delà : deux (« 1,50 Go »).
///
/// ⚠️ `L10n.current` : ne JAMAIS appeler cette fonction dans un isolate
/// (§isolateLeak). [formatCount], lui, reste pur et utilisable partout.
String formatFileSize(int bytes, [AppLocalizations? l10n]) {
  final AppLocalizations l = l10n ?? L10n.current;
  final int b = bytes < 0 ? 0 : bytes;
  const int k = 1024;
  if (b < k) return l.sizeBytes(b);
  String fixed(double v, int digits) =>
      NumberFormat(digits == 0 ? '0' : '0.${'0' * digits}', l.localeName)
          .format(v);
  if (b < k * k) return l.sizeKilobytes(fixed(b / k, 0));
  if (b < k * k * k) return l.sizeMegabytes(fixed(b / (k * k), 1));
  return l.sizeGigabytes(fixed(b / (k * k * k), 2));
}

/// §bootPercent — Séparateur de milliers : « 53 781 » se lit, « 53781 » non.
///
/// ⚠️ Écrit à la main plutôt que via `intl` : cette fonction est appelée DANS
/// un isolate de parsing, où l'on ne veut ni initialisation de locale, ni
/// dépendance supplémentaire, ni allocation superflue par entrée.
///
/// ⚠️ Espace ORDINAIRE (U+0020), et pas l'espace fine insécable U+202F que la
/// typographie française appellerait ici. Le seul consommateur est l'écran de
/// démarrage, rendu en **Source Code Pro** : un glyphe absent de la police n'y
/// donnerait pas un espace un peu trop large, mais un carré vide — et sur un
/// téléviseur, personne ne serait là pour le voir.
const String _thousandsSeparator = ' ';

String formatCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(_thousandsSeparator);
    b.write(s[i]);
  }
  return b.toString();
}

/// Revue 2026-09-11, lot 7 (relecture) — Un nombre groupé dans la langue de
/// l'ÉCRAN : « 12 400 » en français (exactement [formatCount], rien ne bouge),
/// « 12,400 » en anglais. Le groupement français à l'espace appliqué à un
/// écran anglais (« 12 400 votes », « 153 062 entries ») se lisait comme une
/// traduction oubliée.
///
/// ⚠️ `L10n` / `intl` : isolate PRINCIPAL uniquement. Dans un isolate,
/// [formatCount] reste la seule option (§isolateLeak).
String formatCountFor(int n, AppLocalizations l) =>
    l.localeName.startsWith('fr')
        ? formatCount(n)
        : NumberFormat.decimalPattern(l.localeName).format(n);

String formatDuration(int totalSeconds) {
  if (totalSeconds < 0) return "--:--";
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return (duration.inHours > 0) ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
}

/// Revue 2026-09-11, D1B-07 / D1B-19 — Une durée courte lisible : « 2h10 »,
/// « 45 min ». Remplace trois copies de `'${h}h$m' : '$m min'` (santé de
/// lecture, replay, guide des chaînes) écrites en dur.
String formatShortDuration(Duration d, [AppLocalizations? l10n]) {
  final AppLocalizations l = l10n ?? L10n.current;
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  return h > 0
      ? l.durationHoursMinutes(h, m.toString().padLeft(2, '0'))
      : l.durationMinutes(m);
}

/// Revue 2026-09-11, D1A-07 — Un DÉLAI d'attente : « 3 min », « 25 s ».
String formatShortDelay(Duration d, [AppLocalizations? l10n]) {
  final AppLocalizations l = l10n ?? L10n.current;
  final int s = d.inSeconds;
  if (s >= 60 && s % 60 == 0) return l.durationMinutes(s ~/ 60);
  return l.durationSeconds(s);
}
