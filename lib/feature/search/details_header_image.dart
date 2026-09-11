/// §posterFlash — Quelle image la fiche montre AVANT que TMDB réponde.
///
/// ## Le constat, mesuré sur le Galaxy S25 (2026-09-10)
///
/// À l'ouverture de la fiche « Heroes », l'affiche de **Speed 2: Cruise
/// Control** apparaissait pendant ~1 s, toujours la même, puis la bonne image
/// la remplaçait.
///
/// Ce n'était pas un défaut d'affichage : c'est la **donnée du fournisseur qui
/// est fausse**. L'entrée Heroes de la plus grosse liste porte
/// `backdrop = …/series/k49HUkn5a1BOmHGVLU2TUgsHzD5.jpg`, et cette image EST
/// celle de Speed 2 (téléchargée et regardée). Une seconde plus tard, TMDB
/// répond et corrige.
///
/// ⚠️ **Le correctif de §posterFlash livré le 2026-09-09 (`ValueKey(url)` sur
/// `AetherImage`) visait l'AUTRE cause** — la vignette recyclée qui gardait
/// l'image précédente. Il était juste, et il ne pouvait rien contre celle-ci.
///
/// ## Pourquoi c'était toujours la MÊME mauvaise image
///
/// La politique §23 (« plus grosse liste ») trie les versions par nombre
/// d'entrées du compte : le tri est stable, donc le même compte gagne à chaque
/// ouverture. Rien d'aléatoire, contrairement à un recyclage de vignette —
/// c'est ce déterminisme qui a mis sur la piste.
///
/// ## La règle retenue : la fiche montre CE QUE LA VIGNETTE MONTRAIT
///
/// ⚠️ La vignette d'accueil n'affiche **que des `logoUrl`**
/// (`ParsedPlaylistService.logoCandidates`) — elle ne regarde JAMAIS le
/// `backdropUrl`. La fiche, elle, préférait le backdrop (format paysage, idéal
/// pour un en-tête). Résultat : elle affichait un champ que l'œil de
/// l'utilisateur n'avait jamais validé ailleurs, et donc un champ dont
/// personne ne pouvait remarquer qu'il était faux.
///
/// Les affiches passent donc devant, et le décor du fournisseur ne sert plus
/// qu'en **dernier** recours. Le coût est cosmétique et dure une seconde : une
/// affiche 2:3 recadrée dans un en-tête 16:9, au lieu d'un paysage. Le gain est
/// qu'on ne montre plus, en grand, une donnée que rien n'a jamais vérifiée.
///
/// ⛔ Ne pas « rétablir le backdrop en tête pour la beauté du cadrage » sans
/// avoir d'abord un moyen de vérifier ce champ. Et ⛔ ne pas en conclure que
/// les backdrops sont globalement moins fiables que les affiches : **un seul
/// titre a été mesuré**. Ce qui est établi, c'est que ce champ-là n'est
/// confronté à aucun regard, nulle part ailleurs dans l'app.
library;

/// L'image d'en-tête à afficher tant que TMDB n'a pas répondu, ou `null` si
/// aucune adresse n'est disponible.
///
/// Les paramètres arrivent dans l'ordre où ils sont ESSAYÉS. **Pure** — testée.
String? playlistHeaderImage({
  /// L'affiche du groupe (politique « plus grosse liste ») — exactement ce que
  /// la vignette d'accueil affiche.
  required String? groupLogo,

  /// L'affiche de l'épisode couramment sélectionné, s'il y en a un.
  required String? episodeLogo,

  /// L'affiche de la version sur laquelle l'utilisateur a tapé.
  required String? entryLogo,

  /// ⚠️ Le décor du fournisseur : en DERNIER, voir l'en-tête de fichier.
  required String? groupBackdrop,
  required String? entryBackdrop,
}) {
  for (final String? candidate in <String?>[
    groupLogo,
    episodeLogo,
    entryLogo,
    groupBackdrop,
    entryBackdrop,
  ]) {
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  return null;
}
