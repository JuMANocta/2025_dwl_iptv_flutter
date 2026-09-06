import '../../data/models/m3u_entry.dart';
import 'm3u_filter.dart';

/// §detailsLive — Ce qu'une fiche doit savoir de la MÉMOIRE, en règles pures.
///
/// **Le défaut réparé.** Une fiche de FILM figeait ses versions au moment du
/// tap : elle affichait la liste que l'accueil lui avait passée et ne la
/// recalculait plus jamais. Quand une liste revenait (rechargement, ré-analyse
/// terminée, retour de mémoire), ses qualités n'apparaissaient qu'après avoir
/// refermé puis rouvert la fiche. Les séries, elles, repartaient bien de la
/// mémoire à l'ouverture (`_buildSeasonEpisodes`) — mais n'écoutaient pas
/// davantage les changements.
///
/// Ces trois règles sont sorties de la page parce qu'elles étaient écrites
/// DEUX fois (une pour les films, une pour les séries) et que c'est
/// exactement comme ça que les deux chemins avaient divergé.

/// Toutes les entrées d'un vivier qui appartiennent au même titre que [ref] :
/// les versions d'un film, les stubs et épisodes d'une série.
///
/// La règle de rapprochement est celle de l'accueil : clé de groupe insensible
/// à la casse (fusion cross-listes), plus le garde-fou **§homonymYear** — si le
/// titre ouvert porte une année, on ne ramasse que les entrées de la MÊME
/// année ou sans année, pour ne pas mélanger deux films homonymes d'époques
/// différentes (« Vengeance » 1990 et 2022).
List<M3uEntry> entriesOfTitle(Iterable<M3uEntry> pool, M3uEntry ref) {
  // Entrée synthétique (§tmdbOnlyDetails) : aucune source, rien à rapprocher.
  if (ref.url.isEmpty) return const <M3uEntry>[];
  final String key = contentGroupKey(ref);
  final String? year = ref.title.year;
  return pool
      .where((e) =>
          e.type == ref.type &&
          contentGroupKey(e) == key &&
          (year == null || e.title.year == null || e.title.year == year))
      .toList();
}

/// Empreinte comparable de ce que la mémoire contient pour un titre.
///
/// Elle sert à ne RIEN reconstruire quand un bump de version de la playlist ne
/// concerne pas la fiche ouverte — et il y en a beaucoup : un rechargement de
/// trois listes en produit au moins trois.
String versionsSignature(List<M3uEntry> entries) {
  final List<String> urls = entries.map((e) => e.url).toList()..sort();
  return '${urls.length}:${urls.join(' ')}';
}

/// La version à garder sélectionnée après un recalcul.
///
/// ⚠️ Garder la sélection courante si elle existe TOUJOURS : sinon la reprise
/// de lecture et le bouton LIRE sautent sous les doigts de l'utilisateur au
/// moment précis où une liste revient. Si elle a disparu (liste retirée,
/// source périmée), on retombe sur la première — jamais sur rien.
M3uEntry? keepSelection(List<M3uEntry> versions, String currentUrl) {
  if (versions.isEmpty) return null;
  for (final M3uEntry v in versions) {
    if (v.url == currentUrl) return v;
  }
  return versions.first;
}
