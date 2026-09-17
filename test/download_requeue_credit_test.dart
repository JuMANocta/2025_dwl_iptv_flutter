// §dlQueueFix (recette AVD du 2026-09-17) — un fournisseur réel ferme la
// connexion toutes les ~30 s ; chaque reprise avançait de ~290 Mo mais les
// trois crédits n'étaient jamais rendus : le film tombait en échec en plein
// progrès. Ces tests tombent si `effectiveRequeues` cesse de rendre les crédits
// sur avancée, ou les rend sans avancée (boucle sans fin sur une source morte).
import 'package:aetherStream/data/services/download_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucune remise en file encore : rien à rendre', () {
    expect(
        effectiveRequeues(requeues: 0, bytesAtLastRequeue: null, bytesNow: 5),
        0);
  });

  test('le transfert a avancé de plus du seuil : les crédits sont rendus', () {
    expect(
        effectiveRequeues(
            requeues: 2,
            bytesAtLastRequeue: 89 * 1024 * 1024,
            bytesNow: 379 * 1024 * 1024),
        0);
  });

  test('aucune avancée (source morte) : les crédits restent comptés', () {
    expect(
        effectiveRequeues(
            requeues: 2, bytesAtLastRequeue: 1000, bytesNow: 1000 + 4096),
        2);
  });

  test('pile au seuil : rendu ; un octet en dessous : compté', () {
    expect(
        effectiveRequeues(
            requeues: 1,
            bytesAtLastRequeue: 0,
            bytesNow: kRequeueCreditBytes),
        0);
    expect(
        effectiveRequeues(
            requeues: 1,
            bytesAtLastRequeue: 0,
            bytesNow: kRequeueCreditBytes - 1),
        1);
  });

  test('une source morte finit toujours par tomber en échec', () {
    int credits = 0;
    int tours = 0;
    while (shouldRequeueAfterFailure(
        kind: DownloadFailureKind.network,
        requeues: effectiveRequeues(
            requeues: credits, bytesAtLastRequeue: 500, bytesNow: 500))) {
      credits++;
      tours++;
      expect(tours, lessThan(10));
    }
    expect(credits, kMaxNetworkRequeues);
  });
}
