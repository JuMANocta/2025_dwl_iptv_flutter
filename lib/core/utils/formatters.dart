import 'dart:math' as math;

String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  final i = (math.log(bytes) / math.log(1024)).floor();
  return "${(bytes / (1 << (10 * i))).toStringAsFixed(2)} ${suffixes[i]}";
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

String formatDuration(int totalSeconds) {
  if (totalSeconds < 0) return "--:--";
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return (duration.inHours > 0) ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
}