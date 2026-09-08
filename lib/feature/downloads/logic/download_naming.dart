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
/// ⚠️ Un nom sans extension (le cas existe : `_ext()` rend une chaîne vide
/// quand l'URL n'en porte pas) reçoit simplement le suffixe à la fin.
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
