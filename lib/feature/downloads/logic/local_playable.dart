/// §dlPlayLocal (2026-09-16) — Quand un titre a été téléchargé, c'est le
/// FICHIER qu'on lit, pas le flux.
///
/// **Le défaut payé.** Aucun point de lancement de l'app ne regardait les
/// téléchargements : la fiche, l'épisode suivant automatique, la feuille
/// d'appui long et la carte de l'accueil poussaient tous `entry.url`. Seul
/// l'onglet Téléchargements ouvrait un fichier local. Un film téléchargé ne
/// « marchait hors ligne » que si on pensait à passer par cet onglet — et une
/// série téléchargée, jamais, puisqu'on la lance depuis sa fiche.
///
/// **Ce que cette politique décide, et rien d'autre** : parmi les URL du
/// GROUPE (toutes les versions du titre, la sélectionnée en tête), laquelle a
/// un fichier terminé ET présent sur le disque. Elle ne touche ni au réseau,
/// ni au disque, ni à Flutter : l'existence lui est FOURNIE ([exists]), c'est
/// ce qui la rend testable sans appareil.
///
/// ⚠️ **La correspondance est EXACTE, à dessein.** `DownloadTask` n'a que
/// l'URL comme clé (ni compte, ni série, ni saison/épisode). L'URL d'un
/// épisode Xtream porte les identifiants du compte
/// (`hôte/series/user/pass/{id}.{ext}`) : une égalité stricte refuse donc de
/// mélanger deux abonnements qui servent le même titre — c'est voulu, chacun
/// a son fichier. Élargir la correspondance (ignorer l'extension, comparer
/// les titres) ferait lire le fichier d'un autre compte : ⛔ ne pas le faire
/// sans une mesure qui le justifie.
library;

import '../../../data/models/download_task.dart';

/// Ce que [pickLocalPlayable] a trouvé.
///
/// [playable] — la tâche à lire hors ligne, `null` si aucune.
/// [missing] — les tâches TERMINÉES du groupe dont le fichier a disparu du
/// disque (effacé à la main, carte SD retirée, `finalPath` qui n'était que le
/// chemin ATTENDU dans le repli MediaStore). L'appelant les signale : une
/// tâche « Terminé » qui ne se lit pas est un mensonge, et repartir en flux
/// sans le dire ressemble à une panne réseau.
typedef LocalPlayableChoice = ({
  DownloadTask? playable,
  List<DownloadTask> missing,
});

/// La version LOCALE à lire pour ce titre, s'il y en a une.
///
/// [urls] est l'ordre de préférence : l'URL sélectionnée d'abord, puis les
/// autres versions du groupe. La première qui a un fichier présent gagne —
/// pas la « meilleure » qualité : celle que la personne a demandée, sinon
/// n'importe quelle autre version du même titre plutôt qu'un flux.
///
/// [exists] dit si un chemin existe (en production `File(p).existsSync()`,
/// appelé au MOMENT du choix et jamais au démarrage, §bootFast).
LocalPlayableChoice pickLocalPlayable({
  required Iterable<DownloadTask> tasks,
  required List<String> urls,
  required bool Function(String path) exists,
}) {
  final List<DownloadTask> completed = <DownloadTask>[
    for (final t in tasks)
      if (t.status == DownloadStatus.completed) t,
  ];
  if (completed.isEmpty || urls.isEmpty) {
    return (playable: null, missing: const <DownloadTask>[]);
  }

  final List<DownloadTask> missing = <DownloadTask>[];
  final Set<String> seen = <String>{};
  DownloadTask? found;

  // L'ordre des URL EST la préférence : on ne trie pas les tâches.
  for (final String raw in urls) {
    final String url = raw.trim();
    if (url.isEmpty) continue;
    for (final DownloadTask t in completed) {
      if (t.url.trim() != url) continue;
      // Une URL répétée dans le groupe ne doit pas signaler deux fois la même
      // tâche (les versions d'une fiche peuvent partager une URL).
      if (!seen.add(t.id)) continue;
      final String path = t.finalPath.trim();
      if (path.isNotEmpty && exists(path)) {
        // ⚠️ On ne rend pas la main tout de suite : le balayage continue pour
        // que [missing] soit COMPLET. Une tâche terminée dont le fichier a
        // disparu doit être signalée même si une autre version se lit.
        found ??= t;
      } else {
        missing.add(t);
      }
    }
  }

  return (playable: found, missing: missing);
}
