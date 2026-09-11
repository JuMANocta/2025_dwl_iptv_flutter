import 'package:flutter/foundation.dart';

/// §dlPartSweep — Quels fichiers partiels de téléchargement sont ABANDONNÉS.
///
/// ## Le constat (recette Galaxy S25, 2026-09-09)
///
/// Deux partiels de la veille traînaient encore sur l'appareil. Ni le ménage
/// automatique du démarrage ni le bouton d'Optimisation ne pouvaient les voir :
/// `StorageJanitor` ne connaît que `.json`, `.m3u` et `.json.gz`, et il ne
/// regarde que les deux dossiers privés de l'app — jamais le cache externe où
/// vivent les partiels, jamais le dossier public.
///
/// ## ⚠️ Ce qu'un partiel N'EST PAS : un déchet
///
/// Un `.part` est **la seule chose qui rend une reprise possible**. Une tâche
/// en échec garde son `tempPath` à travers les redémarrages, et « Relancer »
/// repart à l'octet exact par un en-tête `Range`. Supprimer le partiel d'une
/// tâche vivante, c'est jeter plusieurs gigaoctets déjà téléchargés.
///
/// D'où la règle, et elle n'a qu'une clause : **un partiel est orphelin s'il
/// n'est le `tempPath` d'AUCUNE tâche connue.** Le statut de la tâche
/// n'entre pas dans la décision — `queued`, `failed`, `canceled`, `paused`
/// désignent tous un fichier reprenable.
///
/// ## ⚠️ Les deux garde-fous
///
/// 1. **L'âge** ([defaultMinimumAge]) — une tâche naît en deux temps : le
///    fichier peut exister une fraction de seconde avant que la tâche soit
///    inscrite. Un fichier récent n'est donc jamais orphelin, seulement jeune.
/// 2. **Le nom, dans le dossier PUBLIC** — ce dossier appartient à
///    l'utilisateur : il y met ce qu'il veut, et §dlOrphans montre justement
///    des films qu'aucune tâche ne connaît. On n'y touche donc **que** ce que
///    l'app a écrit elle-même ([isOwnPartialName]). Jamais un fichier média.
///
/// Le troisième garde-fou n'est pas ici mais chez l'appelant, et c'est le plus
/// important : si la liste des tâches n'a pas pu être relue (préférences qui
/// hoquettent), l'ensemble `liveTempPaths` arrive VIDE et tout devient
/// orphelin. Voir `StorageJanitor.sweepDownloadPartials`.
@immutable
class PartialFile {
  /// Chemin complet — c'est lui qui se compare aux `tempPath` des tâches.
  final String path;
  final int bytes;
  final DateTime modified;

  const PartialFile({
    required this.path,
    required this.bytes,
    required this.modified,
  });

  String get fileName {
    final int slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  @override
  String toString() => 'PartialFile($path, $bytes o)';
}

/// Nom du dossier des fichiers partiels, sous le cache de l'application.
///
/// ⚠️ **Une seule définition**, importée par celui qui l'écrit
/// (`download_initiator`) comme par celui qui le balaie (`StorageJanitor`) :
/// un balayeur qui chercherait dans un dossier au nom périmé ne trouverait
/// jamais rien, et personne ne le verrait.
const String kDownloadTmpDirName = 'dl_tmp';

/// Le dossier des partiels, sous [cacheBase].
///
/// ⚠️ **Composé ici et nulle part ailleurs** : celui qui écrit les partiels
/// (`download_initiator`) et celui qui les balaie (`StorageJanitor`) appellent
/// tous deux cette fonction. Un balayeur qui chercherait dans un dossier au nom
/// périmé ne trouverait jamais rien, et personne ne le verrait. **Pure** —
/// testée.
String downloadTmpPath(String cacheBase) => '$cacheBase/$kDownloadTmpDirName';

/// Délai avant qu'un fichier inconnu soit tenu pour abandonné.
///
/// ⚠️ Généreux à dessein : le coût d'attendre est quelques mégaoctets de plus
/// sur le disque pendant dix minutes ; le coût de se tromper est un
/// téléchargement de plusieurs gigaoctets détruit en cours de route.
const Duration defaultMinimumAge = Duration(minutes: 10);

/// Segment qui marque un fichier partiel écrit par l'app.
///
/// ⚠️ **Il ne peut pas être la DERNIÈRE extension.** Mesuré sur Android 16
/// (émulateur, 2026-09-10) : le dossier `/Movies/AetherStream/` est
/// parfaitement inscriptible, mais le démon FUSE décide **d'après l'extension
/// finale** et refuse tout ce qui n'est pas un média — `.part` comme
/// l'absence d'extension. Le marqueur s'insère donc AVANT l'extension réelle :
/// `.Heat.aetherpart.mkv`. Point de tête → invisible du scanner média et des
/// explorateurs ; `.mkv` final → accepté par le stockage cloisonné.
const String kPartialMarker = 'aetherpart';

/// Le nom du fichier partiel correspondant à [fileName] (`Heat.mkv` →
/// `.Heat.aetherpart.mkv`). **Pure** — testée.
///
/// ⚠️ Un nom sans extension ne peut pas être écrit dans un dossier média : on
/// rend alors une forme qui échouera franchement plutôt qu'un nom trompeur.
String partialNameFor(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '.$fileName.$kPartialMarker';
  final String base = fileName.substring(0, dot);
  final String ext = fileName.substring(dot + 1);
  return '.$base.$kPartialMarker.$ext';
}

/// Ce nom est-il un partiel écrit par l'app dans le dossier PUBLIC ?
///
/// Deux familles, et seulement elles :
/// * `.<nom du film>.<ext>.part` — le partiel du chemin nominal (§dlDirectWrite) ;
/// * `.aether_probe…` / `.aether_write_probe` — un résidu de sonde d'écriture
///   (un octet, effacé aussitôt écrit, mais la suppression peut échouer).
///
/// ⛔ Tout le reste appartient à l'utilisateur. **Pure** — testée.
bool isOwnPartialName(String fileName) {
  if (!fileName.startsWith('.')) return false; // nos partiels sont CACHÉS
  if (fileName.startsWith('.aether_probe') ||
      fileName.startsWith('.aether_write_probe')) {
    return true;
  }
  if (fileName.contains('.$kPartialMarker.')) return true;
  // ⚠️ Forme HISTORIQUE (`.Film.mkv.part`) : elle n'a jamais pu être écrite
  // dans le dossier public — le stockage cloisonné la refusait — mais un
  // appareil permissif a pu en garder. On sait la ramasser, on ne l'écrit plus.
  return fileName.endsWith('.part') && fileName.length > '.part'.length + 1;
}

/// Les fichiers à supprimer, parmi ceux qu'on a trouvés.
///
/// [inPrivateCache] : TOUT le contenu du dossier `dl_tmp`. Ce dossier n'existe
/// que pour ça — chaque fichier qu'il contient est à nous, quel que soit son
/// nom (⚠️ sur le chemin de repli, le partiel porte le nom du fichier FINAL,
/// sans point de tête ni suffixe `.part` : un balayage qui ne chercherait que
/// `*.part` raterait toute cette famille).
///
/// [inPublicFolder] : le contenu du dossier public — filtré par
/// [isOwnPartialName].
///
/// **Pure** — testée.
List<PartialFile> orphanPartials({
  required Iterable<PartialFile> inPrivateCache,
  required Iterable<PartialFile> inPublicFolder,
  required Set<String> liveTempPaths,
  required DateTime now,
  Duration minimumAge = defaultMinimumAge,
}) {
  final List<PartialFile> out = <PartialFile>[];

  void consider(PartialFile f) {
    if (liveTempPaths.contains(f.path)) return; // une tâche peut le reprendre
    if (now.difference(f.modified) < minimumAge) return; // jeune, pas abandonné
    out.add(f);
  }

  for (final PartialFile f in inPrivateCache) {
    consider(f);
  }
  for (final PartialFile f in inPublicFolder) {
    if (!isOwnPartialName(f.fileName)) continue;
    consider(f);
  }
  return out;
}
