/// §inferDelta (2026-09-06, lot 13) — Applique un DELTA de catégories déduites
/// à un rangement déjà calculé, au lieu de le refaire.
///
/// **Le défaut réparé.** `InferredCategoryService.version` entre dans la clé
/// du groupement de l'accueil : chaque catégorie apprise (une affiche TMDB
/// résolue sur un titre sans `group-title`) refaisait le rangement COMPLET des
/// trois pages — mesuré sur l'émulateur TV : 408 + 925 + 128 ms, soit plusieurs
/// secondes sur le processeur d'un téléviseur — et cela tombait exactement au
/// retour du lecteur, quand on venait d'ouvrir la fiche d'un tel titre. Une
/// catégorie apprise ne déplace pourtant qu'UN groupe (deux si le titre est
/// éclaté par année) : c'est ce déplacement, et lui seul, qu'on fait ici.
///
/// Règles reprises de `pickCategory` (`home_page.dart`), dans le même ordre —
/// le résultat doit être celui qu'un regroupement complet aurait donné :
/// 1. une catégorie FOURNIE par la liste (autre que « New ») gagne toujours →
///    la catégorie apprise est sans effet, le groupe ne bouge pas ;
/// 2. sinon le groupe est aujourd'hui dans son ancienne catégorie déduite,
///    dans « New » (étiquette fournisseur des listes SANS horodatage) ou dans
///    « Autres » ; il part dans la catégorie apprise ;
/// 3. §rowFold : si cette catégorie n'existe pas encore, un regroupement
///    complet l'aurait repliée (une rangée d'un seul titre) → le groupe va,
///    ou reste, dans « Autres » tant que le seuil de repli est actif ;
/// 4. une rangée de genre est triée par titre → insertion à sa place.
///
/// ⚠️ « New » VIRTUELLE (catalogue horodaté) DUPLIQUE les groupes : on n'y
/// retire jamais rien. Ce n'est que sur une liste sans horodatage que « New »
/// est la catégorie primaire d'un groupe.
library;

import 'package:aetherStream/data/models/m3u_entry.dart';

/// Ce qu'une clé de groupe a appris : d'où elle vient (`null` = jamais
/// déduite) et où elle va.
typedef InferredChange = ({String? previous, String category});

/// Applique [delta] au rangement [byCategory] (muté EN PLACE).
///
/// [groupsByKey] — index « clé de groupe → groupes » du même rangement.
/// [hasAddedData] — le catalogue porte des horodatages (« New » virtuelle).
/// [rowFoldMin] — seuil de repli des micro-rangées (§rowFold), 1 = désactivé.
/// [isSortedGenre] — les rangées triées par titre (genres) ; les autres
/// gardent l'ordre de la liste.
///
/// Rend `true` si le JEU de rangées a changé (une créée, une vidée) : c'est le
/// signal pour retrier les catégories.
bool applyInferredDelta({
  required Map<String, List<List<M3uEntry>>> byCategory,
  required Map<String, List<List<M3uEntry>>> groupsByKey,
  required Map<String, InferredChange> delta,
  required bool hasAddedData,
  required int rowFoldMin,
  required bool Function(String category) isSortedGenre,
}) {
  var setChanged = false;
  delta.forEach((String key, InferredChange change) {
    final List<List<M3uEntry>>? groups = groupsByKey[key];
    if (groups == null) return;
    for (final List<M3uEntry> group in groups) {
      // 1. La liste a fourni une catégorie : la déduction ne compte pas.
      if (hasProvidedCategory(group)) continue;

      final String? current = _currentCategoryOf(
        group,
        previous: change.previous,
        hasAddedData: hasAddedData,
        byCategory: byCategory,
      );
      // 3. Rangée absente → repliée par un regroupement complet.
      final String target =
          (!byCategory.containsKey(change.category) && rowFoldMin > 1)
              ? 'Autres'
              : change.category;
      if (current == target) continue;

      if (current != null) {
        final List<List<M3uEntry>> from = byCategory[current]!;
        from.remove(group); // identité : une liste n'a pas d'égalité de valeur
        if (from.isEmpty && current != 'Autres') {
          byCategory.remove(current);
          setChanged = true;
        }
      }
      final List<List<M3uEntry>>? dest = byCategory[target];
      if (dest == null) {
        byCategory[target] = <List<M3uEntry>>[group];
        setChanged = true;
      } else if (isSortedGenre(target)) {
        _insertSorted(dest, group); // 4.
      } else {
        dest.add(group);
      }
    }
  });
  return setChanged;
}

/// Une version du groupe porte-t-elle une catégorie fournie par sa liste
/// (autre que l'étiquette « New ») ? Même test que `pickCategory`.
bool hasProvidedCategory(List<M3uEntry> group) {
  for (final M3uEntry e in group) {
    final String? c = e.category;
    if (c != null && c.isNotEmpty && c != 'New') return true;
  }
  return false;
}

/// Où le groupe est rangé aujourd'hui, parmi les seules cases possibles pour
/// un groupe sans catégorie fournie : son ancienne catégorie déduite, « New »
/// (fallback des listes sans horodatage), « Autres ». `null` = introuvable
/// (rangement inconnu : on ne retire rien, on ajoute seulement).
String? _currentCategoryOf(
  List<M3uEntry> group, {
  required String? previous,
  required bool hasAddedData,
  required Map<String, List<List<M3uEntry>>> byCategory,
}) {
  bool holds(String cat) {
    final List<List<M3uEntry>>? list = byCategory[cat];
    if (list == null) return false;
    for (final List<M3uEntry> g in list) {
      if (identical(g, group)) return true;
    }
    return false;
  }

  if (previous != null && previous.isNotEmpty && holds(previous)) {
    return previous;
  }
  if (!hasAddedData && holds('New')) return 'New';
  if (holds('Autres')) return 'Autres';
  return null;
}

/// Insère [group] à sa place dans une rangée triée par titre (même clé de tri
/// que le regroupement complet : `displayName` en minuscules).
void _insertSorted(List<List<M3uEntry>> row, List<M3uEntry> group) {
  final String name = group.first.displayName.toLowerCase();
  int lo = 0;
  int hi = row.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (row[mid].first.displayName.toLowerCase().compareTo(name) <= 0) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  row.insert(lo, group);
}
