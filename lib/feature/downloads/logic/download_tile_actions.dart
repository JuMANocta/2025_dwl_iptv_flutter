import '../../../data/models/download_task.dart';

/// §dlErgo — Actions proposées par une tuile de téléchargement.
enum DownloadAction {
  /// Lire le fichier téléchargé.
  play,

  /// Ouvrir le moniteur (logs + progression). Purement consultatif.
  monitor,

  /// §dlRestart — Coupe le transfert en cours puis relance la MÊME tâche : la
  /// reprise `Range` repart de la taille du fichier partiel, donc sans perdre
  /// la progression.
  restart,

  /// DESTRUCTIF — arrête le transfert. Le fichier partiel est conservé, donc
  /// la reprise reste possible.
  cancel,

  /// DESTRUCTIF — retire la tâche ET efface les fichiers (final + partiel).
  delete,
}

extension DownloadActionX on DownloadAction {
  /// Une action destructive ne doit JAMAIS être l'action principale d'un tap :
  /// c'est l'invariant que verrouille `test/download_tile_actions_test.dart`.
  bool get isDestructive =>
      this == DownloadAction.cancel || this == DownloadAction.delete;
}

/// Action principale (tap / touche OK) + entrées du menu ⋯.
typedef DownloadTileActions = ({
  DownloadAction primary,
  List<DownloadAction> menu,
});

/// §dlErgo — Table des actions d'une tuile selon son statut.
///
/// **Pourquoi cette fonction existe** : avant, `_handleTap` faisait
/// `case downloading → cancelTask` — le geste le plus naturel sur une tuile
/// (et la touche OK sur TV) **annulait le téléchargement sans rien demander**.
/// À l'inverse, `queued`/`paused`/`finalizing` tombaient dans un `default:
/// break` et ne faisaient rien du tout.
///
/// Deux règles, vérifiées par les tests :
///   1. l'action principale n'est **jamais** destructive ;
///   2. **aucun** statut n'est une impasse.
DownloadTileActions downloadTileActions(DownloadStatus status) {
  switch (status) {
    case DownloadStatus.downloading:
      return (
        primary: DownloadAction.monitor,
        menu: const [
          DownloadAction.restart,
          DownloadAction.cancel,
          DownloadAction.delete,
        ],
      );

    case DownloadStatus.queued:
    case DownloadStatus.paused:
      // `restart` sert ici de « forcer le démarrage » : une tâche restée en
      // file doit pouvoir être poussée sans passer par une annulation.
      return (
        primary: DownloadAction.monitor,
        menu: const [
          DownloadAction.restart,
          DownloadAction.cancel,
          DownloadAction.delete,
        ],
      );

    case DownloadStatus.finalizing:
      // Pas d'annulation ici : le transfert réseau est fini, on est sur le
      // `rename` / la copie de repli. Interrompre ne ferait que corrompre.
      return (
        primary: DownloadAction.monitor,
        menu: const [DownloadAction.delete],
      );

    case DownloadStatus.completed:
      // ⚠️ AUCUNE relance ici. Le fichier partiel a été renommé en fichier
      // final : il n'y a plus rien à reprendre, un « relancer » repartirait de
      // ZÉRO et referait plusieurs Go sur une simple faute de frappe. Pour
      // refaire un fichier : le supprimer, puis relancer depuis sa fiche.
      return (
        primary: DownloadAction.play,
        menu: const [DownloadAction.delete],
      );

    case DownloadStatus.failed:
    case DownloadStatus.canceled:
      return (
        primary: DownloadAction.restart,
        menu: const [DownloadAction.delete],
      );
  }
}
