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

  /// Vrai dès qu'au moins une page affiche des listes ou leurs compteurs.
  static bool get hasHolders => holders.value > 0;

  /// Prend un jeton (à appeler dans `initState`).
  static void hold() {
    holders.value = holders.value + 1;
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
  static void reset() => holders.value = 0;
}
