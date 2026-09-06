import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/downloads/logic/download_tile_actions.dart';

/// §dlErgo — Verrouille les deux invariants de la table d'actions.
///
/// Avant correctif, `_handleTap` faisait `case downloading → cancelTask` : le
/// geste le plus naturel sur une tuile (et **la touche OK** sur TV) annulait le
/// téléchargement sans rien demander. À l'inverse, `queued`/`paused`/
/// `finalizing` tombaient dans un `default: break` et ne faisaient rien.
void main() {
  test('INVARIANT — le tap n\'est JAMAIS destructif, quel que soit le statut',
      () {
    for (final s in DownloadStatus.values) {
      final primary = downloadTileActions(s).primary;
      expect(
        primary.isDestructive,
        isFalse,
        reason: '$s met une action destructive ($primary) sur le tap',
      );
    }
  });

  test('INVARIANT — aucun statut n\'est une impasse', () {
    for (final s in DownloadStatus.values) {
      // Un `switch` exhaustif garantit déjà une valeur, mais ce test protège
      // l'ajout d'un futur statut : il échouera si quelqu'un le mappe sur une
      // action vide de sens.
      expect(downloadTileActions(s).primary, isNotNull, reason: '$s');
    }
  });

  test('un téléchargement en cours s\'ouvre sur le moniteur, et peut être '
      'relancé ou arrêté depuis le menu', () {
    final a = downloadTileActions(DownloadStatus.downloading);
    expect(a.primary, DownloadAction.monitor);
    expect(a.menu, contains(DownloadAction.restart));
    expect(a.menu, contains(DownloadAction.cancel));
  });

  test('un téléchargement terminé se lit au tap, et ne propose AUCUNE relance',
      () {
    final a = downloadTileActions(DownloadStatus.completed);
    expect(a.primary, DownloadAction.play);
    // Rien à annuler : le transfert est fini.
    expect(a.menu, isNot(contains(DownloadAction.cancel)));
    // ⚠️ Garde-fou : le fichier partiel a été renommé en fichier final, il n'y
    // a plus rien à reprendre. Une relance repartirait de ZÉRO et referait
    // plusieurs Go sur une simple faute de frappe.
    expect(a.menu, isNot(contains(DownloadAction.restart)));
  });

  test('un échec ou une annulation se relance au tap (§dlRestart)', () {
    for (final s in [DownloadStatus.failed, DownloadStatus.canceled]) {
      expect(downloadTileActions(s).primary, DownloadAction.restart,
          reason: '$s');
    }
  });

  test('pendant la finalisation, aucune annulation proposée', () {
    // Le transfert réseau est terminé : on est sur le rename / la copie de
    // repli. Interrompre ne ferait que corrompre le fichier.
    final a = downloadTileActions(DownloadStatus.finalizing);
    expect(a.menu, isNot(contains(DownloadAction.cancel)));
    expect(a.menu, contains(DownloadAction.delete));
  });

  test('une relance est atteignable sur tout transfert REPRENABLE', () {
    // C'est l'action qu'on cherche quand le débit s'effondre (bridage
    // fournisseur) : elle ne doit jamais manquer tant qu'un fichier partiel
    // existe. Deux exceptions, où il n'y a rien à reprendre :
    //   - `finalizing` : le transfert réseau est déjà terminé ;
    //   - `completed`  : le `.part` a été renommé en fichier final → relancer
    //     repartirait de zéro ;
    //   - `queued` (§dlQueue, 2026-09-06) : rien n'a commencé, et « forcer le
    //     départ » ouvrirait une seconde connexion sur le même abonnement
    //     (403 chez les panels). La file la fera partir d'elle-même.
    const noRestart = {
      DownloadStatus.finalizing,
      DownloadStatus.completed,
      DownloadStatus.queued,
    };
    for (final s in DownloadStatus.values) {
      final a = downloadTileActions(s);
      final hasRestart = a.primary == DownloadAction.restart ||
          a.menu.contains(DownloadAction.restart);
      expect(hasRestart, !noRestart.contains(s), reason: '$s');
    }
  });

  test('la suppression reste accessible depuis TOUS les statuts', () {
    for (final s in DownloadStatus.values) {
      expect(downloadTileActions(s).menu, contains(DownloadAction.delete),
          reason: '$s');
    }
  });

  test('isDestructive ne marque que cancel et delete', () {
    expect(DownloadAction.cancel.isDestructive, isTrue);
    expect(DownloadAction.delete.isDestructive, isTrue);
    expect(DownloadAction.play.isDestructive, isFalse);
    expect(DownloadAction.monitor.isDestructive, isFalse);
    expect(DownloadAction.restart.isDestructive, isFalse);
  });
}
