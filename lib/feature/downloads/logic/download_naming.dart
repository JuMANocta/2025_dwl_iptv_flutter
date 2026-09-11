/// §dlEpisode — Nommer un fichier de téléchargement SANS jamais en écraser un
/// autre.
///
/// **Le défaut payé** (signalé le 2026-09-08) : le bouton « Télécharger » de la
/// fiche passait le seul nom de la SÉRIE (`title.baseTitle`), sans saison ni
/// épisode. Tous les épisodes visaient donc `Movies/AetherStream/Heroes.mp4`,
/// et `_finalizeDownload` les écrasait l'un après l'autre — un `rename` POSIX
/// remplace sa cible **sans erreur ni avertissement**. La liste affichait dix
/// épisodes terminés pour un seul fichier sur l'appareil.
///
/// Le nom est corrigé à la source (`buildDownloadName`), mais ⚠️ **le nom
/// n'était que l'occasion** : l'écrasement silencieux est le défaut de fond, et
/// il reviendrait au premier appelant qui oublierait la saison. D'où cette
/// règle, appliquée aux DEUX bouts — à la création de la tâche, et une dernière
/// fois avant le renommage final (le dossier public est partagé : un fichier a
/// pu y apparaître entre-temps).
library;

/// Nom de fichier candidat n° [index] pour [fileName].
///
/// `0` rend le nom tel quel, puis « nom (2).ext », « nom (3).ext »… Le suffixe
/// se pose **avant l'extension** — `Heroes S01 E02.mp4 (2)` ne serait plus
/// reconnu comme une vidéo par MediaStore ni par les lecteurs.
///
/// ⚠️ Un nom sans extension (tâches enregistrées avant [downloadFileName])
/// reçoit simplement le suffixe à la fin.
String downloadNameCandidate(String fileName, int index) {
  if (index <= 0) return fileName;
  final int dot = fileName.lastIndexOf('.');
  // `dot <= 0` couvre « pas de point » ET « fichier caché » (« .aether »), dont
  // le point de tête n'est pas un séparateur d'extension.
  if (dot <= 0) return '$fileName (${index + 1})';
  final String stem = fileName.substring(0, dot);
  final String ext = fileName.substring(dot); // point inclus
  return '$stem (${index + 1})$ext';
}

/// Caractères interdits dans un nom de fichier, remplacés par `_`.
///
/// ⚠️ `#` et `%` en font partie (revue 2026-09-11, D3A-10) : le repli
/// MediaStore dérive le nom d'un `Uri.parse` du chemin, où `#` coupe le nom au
/// fragment (« #Alive » → vide) et `%` lève une `FormatException`.
String sanitizeFilename(String filename) =>
    filename.replaceAll(RegExp(r'[\\/*?:"<>|#%]'), '_');

/// Extension du fichier désigné par [url], lue sur le DERNIER SEGMENT du
/// chemin (jamais sur la requête), en minuscules. `null` si ce segment n'en
/// porte pas de plausible.
///
/// ⚠️ Revue 2026-09-11 (D3A-04) : l'ancienne lecture prenait tout ce qui
/// suivait le dernier point de l'URL ENTIÈRE. Sur une URL sans extension
/// (`http://1.2.3.4:8080/movie/u/p/123`), le « type de fichier » devenait
/// « 4:8080/movie/u/p/123 » — l'hôte et les identifiants s'affichaient dans la
/// boîte de confirmation et finissaient dans le nom du fichier.
String? urlFileExtension(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return null;
  final List<String> segs =
      uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final String last = segs.last;
  final int dot = last.lastIndexOf('.');
  if (dot <= 0 || dot == last.length - 1) return null;
  final String ext = last.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : null;
}

/// Nom du fichier à écrire pour [name] (+ [year]) téléchargé depuis [url].
///
/// L'extension vient de l'URL (`mp4` à défaut) et est TOUJOURS posée, sauf si
/// le nom se termine déjà par elle.
///
/// ⚠️ Revue 2026-09-11 (D3A-04) : l'ancien test « le nom a-t-il déjà une
/// extension ? » regardait le DERNIER POINT du nom. « Mr. Robot S01 E01 » ou
/// « … Vol. 2 (2017) » passaient donc pour déjà pourvus : fichier écrit SANS
/// extension, partiel en `.Mr.aetherpart. Robot S01 E01` — la forme exacte
/// que le stockage cloisonné refuse (§dlProbeShape), d'où le repli à 2× la
/// taille du film puis un nom que MediaStore n'accepte pas comme vidéo.
String downloadFileName({
  required String name,
  String? year,
  required String url,
}) {
  String base = sanitizeFilename(name);
  if (year != null && year.isNotEmpty) base = '$base ($year)';
  final String ext = urlFileExtension(url) ?? 'mp4';
  if (!base.toLowerCase().endsWith('.$ext')) base = '$base.$ext';
  return base;
}

/// Le premier nom candidat que [taken] ne refuse pas.
///
/// [taken] répond « ce nom est déjà pris » — par une tâche existante, par un
/// fichier sur le disque, ou les deux : c'est l'appelant qui sait, cette
/// fonction ne touche à rien.
///
/// ⚠️ [maxTries] borne la recherche : sans plafond, un dossier pathologique
/// ferait boucler le tap de l'utilisateur. Au-delà, on rend le dernier
/// candidat — le transfert vaut mieux qu'un bouton qui ne répond pas, et
/// l'écrasement éventuel reste alors sous le contrôle du garde-fou de
/// finalisation.
String uniqueDownloadName(
  String fileName, {
  required bool Function(String candidate) taken,
  int maxTries = 99,
}) {
  for (int i = 0; i < maxTries; i++) {
    final String candidate = downloadNameCandidate(fileName, i);
    if (!taken(candidate)) return candidate;
  }
  return downloadNameCandidate(fileName, maxTries);
}
