import 'package:aetherStream/feature/boot/boot_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// §bootFit (2026-09-21) — Sur l'AVD TV, au premier démarrage, le journal
/// (six étapes) plus « Entrer sans attendre » dépassait l'écran : le logo
/// sortait par le haut. L'écran ne garde que les DERNIÈRES étapes terminées.
void main() {
  test('sous la limite : tout reste, dans l\'ordre', () {
    expect(visibleBootHistory([1, 2, 3], max: 4), [1, 2, 3]);
  });

  test('au-delà : les plus anciennes sortent par le haut', () {
    expect(visibleBootHistory([1, 2, 3, 4, 5, 6], max: 4), [3, 4, 5, 6]);
  });

  test('la TV garde moins de lignes que le téléphone', () {
    expect(maxVisibleBootSteps(isTv: true), lessThan(maxVisibleBootSteps(isTv: false)));
    // Mesuré sur l'AVD TV (boot_10) : cinq lignes + l'étape courante + la
    // sortie tenaient à peine ; quatre laissent une ligne de marge.
    expect(maxVisibleBootSteps(isTv: true), lessThanOrEqualTo(4));
  });
}
