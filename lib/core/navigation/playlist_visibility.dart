import 'package:flutter/foundation.dart';

/// §unloadGuard (généralisé) — Qui REGARDE les listes en ce moment.
///
/// **Le défaut corrigé** : le garde du déchargement paresseux ne connaissait
/// qu'une seule page — l'accueil (`HomePage.isForeground && _navIndex == 0`).
/// Rester cinq minutes sur la page « Comptes », qui affiche justement l'état et
/// les compteurs de chaque liste, déclenchait donc `unloadIdleSecondaries`
/// **sous les yeux de l'utilisateur** : les chips passaient à « NON CHARGÉ »
/// et les compteurs à zéro sans qu'aucun échec n'ait eu lieu. La page qui
/// rapporte l'état était celle qui le détruisait.
///
/// Le remède est un simple **compteur de détenteurs** : toute page qui affiche
/// des listes (ou seulement leurs compteurs) prend un jeton en `initState` et
/// le rend en `dispose`. Tant qu'il reste un détenteur, rien n'est déchargé.
///
/// Pourquoi un compteur et pas un booléen : deux pages peuvent se superposer
/// (Comptes poussée par-dessus l'accueil, une feuille par-dessus Comptes), et
/// la fermeture de la seconde ne doit pas lever la protection de la première.
///
/// ⚠️ Ce compteur **ne remplace pas** la protection du compte principal courant
/// (`currentAccountIdNotifier` + `markAccessed`) dans `MainNavigation` : ce
/// garde-là a été payé par un bug où 3 comptes sur 4 se vidaient. Les deux
/// cohabitent.
class PlaylistVisibility {
  PlaylistVisibility._();

  /// Nombre de pages actuellement à l'écran qui montrent des listes.
  /// Exposé en `ValueNotifier` pour rester observable (tests, diagnostic).
  static final ValueNotifier<int> holders = ValueNotifier<int>(0);

  /// R3 (D4A-01) — Jetons d'ONGLET : ceux des pages qui vivent dans
  /// l'`IndexedStack` de `MainNavigation`.
  ///
  /// **Le défaut payé** : ces pages ne sont jamais démontées. L'accueil garde
  /// donc son jeton pendant qu'on est sur l'onglet Téléchargements ou
  /// Recherche — or son jeton veut dire « quelqu'un REGARDE les listes », pas
  /// « la page existe encore ». Résultat : `unloadIdleSecondaries` (§lazyUnload,
  /// profil Léger) ne se déclenchait JAMAIS, et une box à 1 Go gardait
  /// plusieurs dizaines de milliers d'entrées en mémoire pour rien.
  ///
  /// Un jeton d'onglet ne compte donc que tant que son onglet est AFFICHÉ.
  /// Les jetons ordinaires ([hold]), eux, appartiennent à des pages poussées
  /// (Comptes, Optimisation) qui, elles, sont bien à l'écran : ils comptent
  /// toujours, quel que soit l'onglet dessous.
  static final ValueNotifier<bool> tabVisible = ValueNotifier<bool>(true);

  /// Nombre de jetons d'onglet en cours.
  static final ValueNotifier<int> tabHolders = ValueNotifier<int>(0);

  /// Vrai dès qu'au moins une page affiche des listes ou leurs compteurs.
  static bool get hasHolders =>
      holders.value > 0 || (tabHolders.value > 0 && tabVisible.value);

  /// Prend un jeton (à appeler dans `initState`).
  static void hold() {
    holders.value = holders.value + 1;
  }

  /// R3 — Prend un jeton d'ONGLET (page de l'`IndexedStack`).
  static void holdTab() {
    tabHolders.value = tabHolders.value + 1;
  }

  /// R3 — Rend un jeton d'onglet. Borné à zéro, pour la même raison que
  /// [release].
  static void releaseTab() {
    final int next = tabHolders.value - 1;
    tabHolders.value = next < 0 ? 0 : next;
  }

  /// R3 — Dit si l'onglet porteur des listes est celui qu'on regarde.
  /// Appelé au changement d'onglet par `MainNavigation`.
  static void setTabVisible(bool visible) {
    if (tabVisible.value != visible) tabVisible.value = visible;
  }

  /// Rend un jeton (à appeler dans `dispose`).
  ///
  /// Borné à zéro : un `release()` en trop (double `dispose`, hot reload) ne
  /// doit jamais rendre le compteur négatif, sinon la protection deviendrait
  /// impossible à réarmer pour le reste de la session.
  static void release() {
    final int next = holders.value - 1;
    holders.value = next < 0 ? 0 : next;
  }

  /// Remise à zéro — tests uniquement.
  @visibleForTesting
  static void reset() {
    holders.value = 0;
    tabHolders.value = 0;
    tabVisible.value = true;
  }
}
