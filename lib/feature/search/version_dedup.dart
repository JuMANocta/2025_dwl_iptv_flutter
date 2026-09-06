import '../../data/models/m3u_entry.dart';

/// §reloadScope — Dédoublonnage des versions d'une fiche (les pastilles
/// « 4K · FR / Platinium », « HD / PremiumV2 »…).
///
/// **Le défaut réparé.** La clé de dédoublonnage n'incluait la liste d'origine
/// que si `ParsedPlaylistService.isMultiAccount` était vrai — c'est-à-dire si
/// **plusieurs listes étaient chargées EN MÉMOIRE à cet instant**. Dès qu'il
/// n'en restait qu'une (pendant un rechargement, après un déchargement, tant
/// qu'une liste n'était pas revenue), deux versions de même libellé venues de
/// deux listes différentes fusionnaient : une pastille disparaissait purement
/// et simplement, et l'utilisateur ne pouvait plus choisir sa source.
///
/// La liste d'origine fait donc TOUJOURS partie de la clé. En mono-compte le
/// résultat est identique — toutes les entrées portent le même `accountId` —,
/// donc il n'y a rien à conditionner. C'est déjà la règle que suivent les
/// boutons des feuilles d'action (`quality_buttons.dart`) : deux règles pour la
/// même question, une seule était juste.
///
/// [label] rend le libellé affiché d'une version (qualité, langue, marqueur) :
/// c'est lui qui dit ce que deux entrées ont d'identique. L'ordre d'entrée est
/// conservé — la première rencontrée gagne, et l'appelant classe déjà ses
/// versions par priorité.
List<M3uEntry> dedupeVersions(
  List<M3uEntry> versions,
  String Function(M3uEntry entry, int index) label,
) {
  final seen = <String>{};
  final result = <M3uEntry>[];
  for (int i = 0; i < versions.length; i++) {
    final M3uEntry v = versions[i];
    if (seen.add('${label(v, i)}|${v.accountId}')) result.add(v);
  }
  return result;
}
