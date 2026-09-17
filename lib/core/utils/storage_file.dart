export '../platform/storage_service.dart';

/// R14 (D1B-22) — La permission « vidéos » conditionne-t-elle l'ÉCRITURE de
/// nos propres fichiers dans `Movies/AetherStream/` ?
///
/// **Non, à partir d'Android 10 (API 29).** Le stockage cloisonné donne à
/// chaque application le droit de créer et d'écrire SES fichiers dans les
/// dossiers média partagés, sans aucune permission ; `READ_MEDIA_VIDEO` ne
/// sert qu'à LIRE ceux des autres — chez nous, à retrouver les fichiers d'une
/// installation précédente (`DeviceLibraryService`, §dlOrphans).
///
/// **Le défaut payé** : `getAppMoviesPath` demandait la permission d'entrée de
/// jeu et rendait `null` au moindre refus. Un refus — que Google Play refusera
/// lui-même d'accorder pour un usage comme le nôtre — ANNULAIT donc le
/// téléchargement, alors que tout le chemin d'écriture était disponible.
///
/// ⚠️ Avant Android 10, écrire hors du bac à sable exige bien
/// `WRITE_EXTERNAL_STORAGE` : là, un refus est un vrai mur.
bool storagePermissionNeededToWrite(int sdkInt) => sdkInt < 29;
