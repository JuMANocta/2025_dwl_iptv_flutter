import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/navigation/playlist_visibility.dart';

/// §unloadGuard (généralisé) — Le garde du déchargement paresseux ne connaissait
/// qu'une seule page, l'accueil. Rester cinq minutes sur la page « Comptes »,
/// qui affiche justement l'état et les compteurs de chaque liste, déclenchait
/// donc le déchargement **sous les yeux de l'utilisateur** : les chips
/// passaient à « NON CHARGÉ » sans qu'aucun échec n'ait eu lieu.
///
/// Ce compteur est ce qui généralise la protection. Les deux pièges qu'il doit
/// tenir sont ici : l'empilement de pages, et le `release()` en trop.
void main() {
  setUp(PlaylistVisibility.reset);

  test('aucun détenteur au départ → rien ne protège les listes', () {
    expect(PlaylistVisibility.hasHolders, isFalse);
  });

  test('un détenteur suffit à suspendre le déchargement', () {
    PlaylistVisibility.hold();
    expect(PlaylistVisibility.hasHolders, isTrue);
    PlaylistVisibility.release();
    expect(PlaylistVisibility.hasHolders, isFalse);
  });

  test('pages empilées : fermer la seconde ne lève PAS la protection', () {
    // Comptes poussée par-dessus l'accueil, puis une feuille par-dessus
    // Comptes : c'est la raison d'être du compteur plutôt qu'un booléen.
    PlaylistVisibility.hold();
    PlaylistVisibility.hold();
    PlaylistVisibility.release();
    expect(PlaylistVisibility.hasHolders, isTrue,
        reason: 'la page du dessous regarde toujours les listes');
    PlaylistVisibility.release();
    expect(PlaylistVisibility.hasHolders, isFalse);
  });

  test('un release() en trop ne rend jamais le compteur négatif', () {
    // ⚠️ Sinon un `dispose` doublé (ou un hot reload) rendrait la protection
    // impossible à réarmer pour tout le reste de la session : le prochain
    // `hold()` ramènerait le compteur à 0, donc « personne ne regarde ».
    PlaylistVisibility.release();
    PlaylistVisibility.release();
    expect(PlaylistVisibility.holders.value, 0);
    PlaylistVisibility.hold();
    expect(PlaylistVisibility.hasHolders, isTrue);
  });
}
