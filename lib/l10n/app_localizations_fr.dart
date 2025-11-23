// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get downloadManagerTitle => 'Gestion des Téléchargements';

  @override
  String get noDownloads => 'Aucun téléchargement';

  @override
  String get downloadDialogTitle => 'Démarrer le téléchargement';

  @override
  String get downloadDialogFileNameLabel => 'Nom du fichier';

  @override
  String get downloadDialogFileSizeLabel => 'Taille du fichier';

  @override
  String get downloadDialogFileTypeLabel => 'Type de fichier';

  @override
  String get downloadDialogUnknownSize => 'Inconnue';

  @override
  String get cancel => 'Annuler';

  @override
  String get download => 'Télécharger';

  @override
  String get denied =>
      'Permission refusée. Le téléchargement ne peut pas commencer.';

  @override
  String get terminalTitle => '//:INTERFACE_FLUX_TELECHARGEMENT';

  @override
  String terminalResumeMessage(Object fileName) {
    return '🔄 Reprise du téléchargement :\n🎞️ $fileName';
  }

  @override
  String terminalStartMessage(Object fileName) {
    return '🤖 Lancement du téléchargement :\n🎞️ $fileName';
  }

  @override
  String terminalFileSizeMessage(Object fileSize) {
    return '📦 Taille du fichier : $fileSize';
  }

  @override
  String get terminalFinalizingMessage =>
      '\n⚙️ Finalisation...\nDéplacement du fichier vers le stockage public. Veuillez patienter.';

  @override
  String get terminalSuccessMessage => '\n🟢 SUCCÈS : Téléchargement terminé !';

  @override
  String get terminalFatalErrorMessage =>
      '\n☣️ FATAL : Une erreur est survenue';

  @override
  String get terminalCancelMessage =>
      '\nℹ️ ABANDON : Téléchargement annulé par l\'utilisateur';

  @override
  String get terminalCloseButton => '[ FERMER ]';

  @override
  String get terminalAbortingButton => '[ ABANDON... ]';

  @override
  String get terminalAbortButton => '[ ABANDONNER ]';

  @override
  String get searchPageDefaultTitle => 'AetherStream';

  @override
  String get searchPageDownloadsTooltip => 'Voir les téléchargements';

  @override
  String get searchPageReloadTooltip => 'Recharger la playlist';

  @override
  String get searchPageAccountsTooltip => 'Comptes et Paramètres';

  @override
  String get searchPageLoadingError => 'Impossible de charger la playlist';

  @override
  String get searchPageRetryButton => 'Réessayer';

  @override
  String get searchPageProcessingError =>
      'Erreur de traitement de la playlist :';

  @override
  String get searchFieldHint => 'Rechercher...';

  @override
  String get searchFilterFilms => 'Films';

  @override
  String get searchFilterSeries => 'Séries';

  @override
  String get searchFilterTv => 'TV';

  @override
  String get searchNoResults => 'Aucun résultat trouvé.';

  @override
  String get searchNoContent => 'Aucun contenu à afficher.';

  @override
  String get actionSheetChooseVersion => 'Choisir une version pour :';

  @override
  String chipSeasons(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Saisons',
      one: '1 Saison',
    );
    return '$_temp0';
  }

  @override
  String chipEpisodes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ép.',
      one: '1 Ép.',
    );
    return '$_temp0';
  }

  @override
  String get season => 'Saison';

  @override
  String get episode => 'Épisode';

  @override
  String get actionSheetPlay => 'Lire';

  @override
  String get actionSheetPlaySubtitle =>
      'Lance la lecture (mise en cache automatique).';

  @override
  String get actionSheetDownload => 'Télécharger en arrière-plan';

  @override
  String get actionSheetDownloadSubtitle =>
      'Pour regarder plus tard sans connexion.';

  @override
  String get deleteDialogTitle => 'Supprimer le fichier ?';

  @override
  String get deleteDialogSizeLabel => 'Taille';

  @override
  String get deleteDialogWarning =>
      'Cette action est irréversible et le fichier sera définitivement effacé.';

  @override
  String get deleteDialogConfirmButton => 'Supprimer';

  @override
  String get deleteTooltip => 'Supprimer définitivement';

  @override
  String get taskStatusDownloading => 'Téléchargement en cours...';

  @override
  String taskStatusRemaining(Object remainingSize) {
    return ' • $remainingSize restant';
  }

  @override
  String taskStatusCompleted(Object date, Object size) {
    return 'Terminé • $size • $date';
  }

  @override
  String taskStatusFailed(Object progressInfo) {
    return 'Échec $progressInfo • Appuyer pour relancer';
  }

  @override
  String taskStatusCanceled(Object progressInfo) {
    return 'Annulé $progressInfo • Appuyer pour relancer';
  }

  @override
  String taskStatusPending(Object date) {
    return 'En attente • $date';
  }
}
