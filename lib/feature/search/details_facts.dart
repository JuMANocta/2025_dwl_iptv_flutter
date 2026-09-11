import '../../data/models/media_model.dart';

/// §tmdbInfo (2026-09-06) — Les faits que l'encadré « Infos » de la fiche
/// affiche, mis en forme. Règles PURES, sorties de la page pour être testées :
/// chacune porte un piège qui, seul, ferait dire une bêtise à l'écran.

/// « S02E05 · 12/03/2026 — Le Retour ».
///
/// ⚠️ C'est une date de **DIFFUSION annoncée**, pas une disponibilité : la
/// fiche l'écrit comme une annonce et ne la rend jamais cliquable.
String? nextEpisodeLabel(NextEpisodeInfo? n, {String lang = 'fr'}) {
  if (n == null) return null;
  final parts = <String>[];
  if (n.seasonNumber != null && n.episodeNumber != null) {
    parts.add('S${_two(n.seasonNumber!)}E${_two(n.episodeNumber!)}');
  }
  final String? date = shortDate(n.airDate, lang: lang);
  if (date != null) parts.add(date);
  final String head = parts.join(' · ');
  final String? title = (n.name?.isNotEmpty == true) ? n.name : null;
  if (head.isEmpty) return title;
  return title == null ? head : '$head — $title';
}

/// Date ISO → `12/03/2026` (français) ou `3/12/2026` (anglais).
///
/// ⚠️ **Format numérique par choix.** L'écrire en toutes lettres demanderait
/// les données de symboles `intl` de CHAQUE langue (`initializeDateFormatting`),
/// donc du poids d'APK (§apkDiet), pour une ligne d'appoint dont l'année figure
/// déjà en haut de la fiche.
///
/// Revue 2026-09-11, lot 7 (recette TV en anglais) — l'ordre jour/mois était
/// imposé à toutes les langues : « 25/06/2026 » sur un écran anglais. [lang]
/// est `AppLocalizations.localeName` ; le français ne change pas d'un
/// caractère.
String? shortDate(String? iso, {String lang = 'fr'}) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  if (lang.startsWith('en')) return '${d.month}/${d.day}/${d.year}';
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Budget / recettes en dollars, groupés par milliers.
///
/// ⚠️ **TMDB rend `0` quand il ne sait pas**, jamais `null` : afficher « 0 $ »
/// ferait passer une absence d'information pour un fait. En dessous de 1, on
/// n'affiche pas la ligne.
///
/// Revue 2026-09-11, lot 7 — « 5 M$ » (symbole après, milliers à l'espace)
/// est la forme FRANÇAISE ; en anglais : « $5M », « $750,000 ».
String? moneyLabel(int? v, {String lang = 'fr'}) {
  if (v == null || v <= 0) return null;
  if (lang.startsWith('en')) {
    if (v >= 1000000) return '\$${_grouped(v ~/ 1000000, ',')}M';
    return '\$${_grouped(v, ',')}';
  }
  if (v >= 1000000) return '${_grouped(v ~/ 1000000)} M\$';
  return '${_grouped(v)} \$';
}

String _two(int v) => v < 10 ? '0$v' : '$v';

String _grouped(int n, [String sep = ' ']) => n
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}$sep');
