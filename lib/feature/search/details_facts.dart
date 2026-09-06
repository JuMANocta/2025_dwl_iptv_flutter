import '../../data/models/media_model.dart';

/// §tmdbInfo (2026-09-06) — Les faits que l'encadré « Infos » de la fiche
/// affiche, mis en forme. Règles PURES, sorties de la page pour être testées :
/// chacune porte un piège qui, seul, ferait dire une bêtise à l'écran.

/// « S02E05 · 12/03/2026 — Le Retour ».
///
/// ⚠️ C'est une date de **DIFFUSION annoncée**, pas une disponibilité : la
/// fiche l'écrit comme une annonce et ne la rend jamais cliquable.
String? nextEpisodeLabel(NextEpisodeInfo? n) {
  if (n == null) return null;
  final parts = <String>[];
  if (n.seasonNumber != null && n.episodeNumber != null) {
    parts.add('S${_two(n.seasonNumber!)}E${_two(n.episodeNumber!)}');
  }
  final String? date = shortDate(n.airDate);
  if (date != null) parts.add(date);
  final String head = parts.join(' · ');
  final String? title = (n.name?.isNotEmpty == true) ? n.name : null;
  if (head.isEmpty) return title;
  return title == null ? head : '$head — $title';
}

/// Date ISO → `12/03/2026`.
///
/// ⚠️ **Format numérique par choix.** L'écrire en toutes lettres demanderait
/// les données de symboles `intl` de CHAQUE langue (`initializeDateFormatting`),
/// donc du poids d'APK (§apkDiet), pour une ligne d'appoint dont l'année figure
/// déjà en haut de la fiche.
String? shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Budget / recettes en dollars, groupés par milliers.
///
/// ⚠️ **TMDB rend `0` quand il ne sait pas**, jamais `null` : afficher « 0 $ »
/// ferait passer une absence d'information pour un fait. En dessous de 1, on
/// n'affiche pas la ligne.
String? moneyLabel(int? v) {
  if (v == null || v <= 0) return null;
  if (v >= 1000000) return '${_grouped(v ~/ 1000000)} M\$';
  return '${_grouped(v)} \$';
}

String _two(int v) => v < 10 ? '0$v' : '$v';

String _grouped(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
