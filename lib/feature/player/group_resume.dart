import '../../data/models/m3u_entry.dart';
import '../../data/services/watch_progress_service.dart' show WatchProgress;
import '../search/series_stub.dart' show isSeriesStubEntry;

/// R52 — La reprise d'un titre à plusieurs versions (qualités, listes) : sa
/// position, ET la version qui doit la relancer.
///
/// **Le défaut réparé** (recette AVD du 2026-09-25) : la feuille d'appui long
/// d'une série affichait « Reprendre à 00:34 » — la reprise la plus récente du
/// groupe, née sur la liste TestTV — puis lançait la PREMIÈRE version jouable
/// du groupe, celle de la liste VOD. La position d'une liste appliquée au flux
/// d'une autre : une lecture sur un autre abonnement, parfois un autre montage.
/// La fiche, elle, reprend sur la bonne version depuis §22.1
/// (`keepSelection(versions, progress.url)`) : même règle ici.
///
/// - [progress] : la plus récente du groupe (même règle que
///   `WatchProgressService.getProgressForAny`, l'ordre départage les
///   égalités) ;
/// - [entry] : la version qui PORTE cette reprise — `null` quand c'est le
///   stub d'une série (§heroSeriesResume : la clé de série dit « regardée
///   récemment », pas quel épisode) ; seule la fiche sait alors retrouver
///   l'épisode, jamais une version prise au hasard.
typedef GroupResume = ({WatchProgress progress, M3uEntry? entry});

/// `null` = rien à reprendre : aucune reprise, ou à peine commencée (≤ 5 s,
/// la même borne que les tuiles « Reprendre » de l'accueil et de la feuille).
///
/// Fonction pure ([progressOf] injecté) : c'est elle qu'on teste.
GroupResume? groupResumeOf(
  Iterable<M3uEntry> versions, {
  required WatchProgress? Function(String url) progressOf,
}) {
  WatchProgress? best;
  M3uEntry? bestEntry;
  for (final M3uEntry v in versions) {
    final WatchProgress? p = progressOf(v.url);
    if (p == null) continue;
    if (best == null || p.lastWatched.isAfter(best.lastWatched)) {
      best = p;
      bestEntry = v;
    }
  }
  if (best == null || bestEntry == null || best.position.inSeconds <= 5) {
    return null;
  }
  return (
    progress: best,
    entry: isSeriesStubEntry(bestEntry) ? null : bestEntry,
  );
}

/// R52 — Les versions du MÊME objet que [entry] parmi [siblings] ([entry] en
/// tête, sans doublon d'URL).
///
/// ⚠️ Pour un épisode, les « frères » d'un titre (`entriesOfTitle`) sont TOUS
/// les épisodes et stubs de la série : reprendre « le plus récent » de ce
/// groupe relancerait un AUTRE épisode. On ne garde que la même saison et le
/// même numéro. Pour un film, toutes les versions comptent.
List<M3uEntry> sameItemVersions(M3uEntry entry, Iterable<M3uEntry> siblings) {
  final int? s = entry.title.seasonNumber;
  final int? n = entry.title.episodeNumber;
  final bool episode = s != null && n != null;
  final Set<String> seen = <String>{entry.url};
  return <M3uEntry>[
    entry,
    for (final M3uEntry v in siblings)
      if ((!episode ||
              (v.title.seasonNumber == s && v.title.episodeNumber == n)) &&
          seen.add(v.url))
        v,
  ];
}
