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
  String get terminalSpeedMessage => 'Vitesse';

  @override
  String get terminalEtaMessage => 'Temps restant';

  @override
  String get terminalCancelMessage =>
      '\nℹ️ ABANDON : Téléchargement annulé par l\'utilisateur';

  @override
  String get terminalCloseButton => '[ FERMER ]';

  @override
  String get terminalAbortingButton => '[ PAUSE... ]';

  @override
  String get terminalAbortButton => '[ PAUSE ]';

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

  @override
  String get taskStatusUnknownError => 'Erreur inconnue';

  @override
  String get playlistManagementTitle => 'Téléchargement de la playlist';

  @override
  String get playlistCardTitle => 'Playlist .m3u';

  @override
  String get playlistCardSubtitleNone =>
      'Aucune playlist téléchargée dans ce contexte.';

  @override
  String playlistCardSubtitleLastFile(Object path) {
    return 'Dernier fichier : $path';
  }

  @override
  String get playlistDownloadButton => 'Télécharger / Mettre à jour';

  @override
  String get playlistDeleteButton => 'Supprimer';

  @override
  String get playlistManagementTip =>
      'Astuce : vous pouvez aussi recharger la playlist depuis la roue crantée ou via l\'icône de rafraîchissement sur l\'écran de recherche.';

  @override
  String get accountsTitle => 'Gestion des Comptes';

  @override
  String get deleteAccountDialogTitle => 'Supprimer le compte ?';

  @override
  String get deleteAccountDialogContent => 'Cette action est définitive.';

  @override
  String get deleteAccountConfirm => 'Supprimer';

  @override
  String get playlistInfoTitle => 'Infos playlist';

  @override
  String get playlistInfoChecking => 'Vérification de la playlist...';

  @override
  String get playlistInfoUnavailable =>
      'Aucune playlist disponible ou erreur de chargement.';

  @override
  String get playlistInfoTryReload => 'Tenter un rechargement';

  @override
  String get playlistInfoLocalFile => 'Fichier playlist local';

  @override
  String get playlistInfoSize => 'Taille';

  @override
  String get playlistInfoLastUpdate => 'Maj';

  @override
  String get playlistInfoEntries => 'Entrées';

  @override
  String get playlistInfoReloadButton => 'Recharger';

  @override
  String get playlistInfoDeleteButton => 'Supprimer';

  @override
  String get accountsListEmpty => 'Ajouter un compte';

  @override
  String accountModeComplete(Object host) {
    return 'Mode: URL complète — $host';
  }

  @override
  String accountModeSeparate(Object host, Object username) {
    return 'Mode: Séparé — $username@$host';
  }

  @override
  String get accountActionEdit => 'Modifier';

  @override
  String get accountActionDelete => 'Supprimer';

  @override
  String get accountsFab => 'Nouveau';

  @override
  String get editAccountTitleAdd => 'Ajouter un compte';

  @override
  String get editAccountTitleEdit => 'Modifier le compte';

  @override
  String get editAccountNameLabel => 'Nom du compte (ex: Salon, Vacances...)';

  @override
  String get editAccountNameHint => 'Mon Compte IPTV';

  @override
  String get editAccountNameRequired => 'Requis';

  @override
  String get editAccountModeUrl => 'URL Complète';

  @override
  String get editAccountModeCredentials => 'Identifiants';

  @override
  String get editAccountFullUrlLabel => 'URL .m3u complète';

  @override
  String get editAccountFullUrlInvalid => 'URL invalide';

  @override
  String get editAccountServerUrlLabel =>
      'URL du serveur (ex: http://host:port)';

  @override
  String get editAccountUsernameLabel => 'Nom d\'utilisateur';

  @override
  String get editAccountPasswordLabel => 'Mot de passe';

  @override
  String get editAccountPlaylistTypeLabel => 'Type de playlist';

  @override
  String get editAccountPlaylistTypeM3u => 'M3U (Standard)';

  @override
  String get editAccountPlaylistTypeSimple => 'Simple (Lien unique)';

  @override
  String get editAccountCookiesLabel => 'Cookies (optionnel)';

  @override
  String get editAccountCookiesHint => 'ex: PHPSESSID=xxxxxx;';

  @override
  String get editAccountSaveButton => 'Enregistrer';

  @override
  String get playerGenericError => 'Impossible de lire ce média.';

  @override
  String get playerLoading => 'Initialisation du lecteur...';

  @override
  String playerLoadingError(Object error) {
    return 'Erreur de chargement: $error';
  }
}
