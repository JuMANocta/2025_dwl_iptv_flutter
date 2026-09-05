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
  String get terminalTitle => '//:FLUX_DOWNLOAD_INTERFACE';

  @override
  String terminalResumeMessage(Object fileName) {
    return '🔄 Reprise du téléchargement :\n🎞️ $fileName';
  }

  @override
  String terminalStartMessage(Object fileName) {
    return 'ℹ️ Lancement du téléchargement :\n🎞️ $fileName';
  }

  @override
  String terminalFileSizeMessage(Object fileSize) {
    return '📦 Taille du fichier : $fileSize';
  }

  @override
  String get terminalFinalizingMessage =>
      '\n⚙️ Finalisation...\nDéplacement du fichier vers le stockage interne. Veuillez patienter.';

  @override
  String get terminalSuccessMessage => '\n🟢 SUCCÈS : Téléchargement terminé !';

  @override
  String get terminalFatalErrorMessage =>
      '\n☣️ FATAL : Une erreur est survenue';

  @override
  String get terminalSpeedMessage => 'Vitesse';

  @override
  String get terminalRetryCountMessage => 'Relances';

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
  String get favoriteAdd => 'Ajouter aux favoris';

  @override
  String get favoriteRemove => 'Retirer des favoris';

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

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get backupTitle => 'Sauvegarde';

  @override
  String get optimizationTitle => 'Optimisation';

  @override
  String get regionFilterTitle => 'Langues / régions';

  @override
  String get themeSettingsTitle => 'Personnalisation';

  @override
  String get tmdbKeyTitle => 'Affiches et infos TMDB';

  @override
  String get xmltvTitle => 'Guide des chaînes';

  @override
  String get webConsoleTitle => 'Console web';

  @override
  String get navHome => 'Accueil';

  @override
  String get navSearch => 'Recherche';

  @override
  String get navDownloads => 'Téléchargements';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get settingsSectionPhone => 'Piloter depuis le téléphone';

  @override
  String get settingsWebConsole => 'Console web';

  @override
  String get settingsWebConsoleSub =>
      'Comptes, sauvegarde, thème, EPG, TMDB + télécommande (QR)';

  @override
  String get settingsSectionSources => 'Sources & comptes';

  @override
  String get settingsAccounts => 'Comptes IPTV';

  @override
  String get settingsAccountsSub => 'Providers, stats playlist & recharger';

  @override
  String get settingsTmdbKey => 'Affiches et infos TMDB';

  @override
  String get settingsTmdbKeySub => 'Affiches, résumés, casting — optionnel';

  @override
  String get settingsXmltv => 'Guide des chaînes';

  @override
  String get settingsXmltvSub => 'EPG XMLTV — TNT France';

  @override
  String get settingsSectionDisplay => 'Affichage';

  @override
  String get settingsRegions => 'Langues / régions';

  @override
  String get settingsRegionsSub =>
      'Masquer le contenu étranger (réduit la mémoire)';

  @override
  String get settingsTheme => 'Personnalisation';

  @override
  String get settingsThemeSub => 'Thème, couleurs, effets cyberpunk';

  @override
  String get settingsOptimization => 'Optimisation';

  @override
  String get settingsOptimizationSub =>
      'Profils performance, hero, vignettes, mémoire';

  @override
  String get settingsSectionBackup => 'Sauvegarde & application';

  @override
  String get settingsBackup => 'Sauvegarde / Restauration';

  @override
  String get settingsBackupSub =>
      'Exporter/importer comptes, TMDB, thème, favoris (.aether chiffré)';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get settingsAboutSub => 'Version + vérification des mises à jour';

  @override
  String get settingsResetUsage => 'Réinitialiser les données d\'usage';

  @override
  String get settingsResetUsageSub =>
      'Vide favoris, reprises & historique (garde comptes & thème)';

  @override
  String get settingsResetTitle => 'Réinitialiser les données ?';

  @override
  String get settingsResetBody =>
      'Vide les favoris, les reprises de lecture (films & séries), l\'historique de recherche et la dernière chaîne regardée.\n\nConserve les comptes IPTV, la clé TMDB, le thème et les filtres langues/régions.\n\nCette action est irréversible.';

  @override
  String get settingsResetConfirm => 'Réinitialiser';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get errNetworkUnreachable =>
      'Connexion impossible : réseau coupé ou serveur injoignable.';

  @override
  String get errTimeout => 'Le serveur a mis trop de temps à répondre.';

  @override
  String get errTimeoutHint =>
      'Le serveur a mis trop de temps à répondre. Vérifie ta connexion ou l\'adresse du serveur.';

  @override
  String get errTls =>
      'Connexion sécurisée refusée par le serveur (certificat).';

  @override
  String get errBadFormat => 'Réponse illisible du serveur (format inattendu).';

  @override
  String get errFileSystem =>
      'Impossible de lire ou d\'écrire le fichier sur l\'appareil.';

  @override
  String get errInternal => 'Une erreur interne est survenue.';

  @override
  String get errBadResponse =>
      'Réponse invalide du serveur. Vérifie l\'adresse.';

  @override
  String errForbidden(int code) {
    return 'Accès refusé par le serveur (HTTP $code). Vérifie les identifiants du compte.';
  }

  @override
  String get errNotFound => 'Adresse introuvable sur le serveur (HTTP 404).';

  @override
  String errServer(int code) {
    return 'Le serveur est en erreur (HTTP $code). Réessaie plus tard.';
  }

  @override
  String errHttp(int code) {
    return 'Le serveur a répondu avec une erreur (HTTP $code).';
  }

  @override
  String get errConnection =>
      'Erreur de connexion : vérifie que tu es en ligne et que le serveur est accessible.';

  @override
  String get errCancelled => 'Opération annulée.';

  @override
  String get errNetworkUnknown => 'Erreur réseau inconnue.';

  @override
  String rowBecauseYouWatched(String title) {
    return 'Parce que tu as regardé « $title »';
  }

  @override
  String get rowTopRated => 'Les mieux notés';

  @override
  String get tmdbRowsBecauseTitle => 'Rangée « Parce que tu as regardé »';

  @override
  String get tmdbRowsBecauseSub =>
      'Des titres proches de ta dernière lecture, choisis parmi tes listes';

  @override
  String get tmdbRowsTopRatedTitle => 'Rangée « Les mieux notés »';

  @override
  String get tmdbRowsTopRatedSub =>
      'Les titres les mieux notés que proposent tes listes';

  @override
  String get perfMinItemsTitle => 'Rangées : minimum de titres';

  @override
  String get perfMinItemsSub =>
      'En dessous, la rangée est repliée dans « Autres » — New et Favoris jamais. 1 = ne jamais replier.';

  @override
  String get dlOnDeviceTitle => 'Sur l\'appareil';

  @override
  String dlOnDeviceSub(int count, String size) {
    return '$count fichier(s) · $size — dans Movies/AetherStream, absents de la liste';
  }

  @override
  String get dlScanTooltip => 'Chercher les fichiers présents sur l\'appareil';

  @override
  String dlScanFound(int count, String size) {
    return '$count fichier(s) sur l\'appareil hors liste ($size)';
  }

  @override
  String get dlScanNothing => 'Rien de nouveau sur l\'appareil';

  @override
  String get dlScanDenied =>
      'Sans l\'accès aux vidéos, le dossier ne peut pas être lu';

  @override
  String get dlOrphanDeleteTitle => 'Supprimer ce fichier ?';

  @override
  String dlOrphanDeleteBody(String name, String size) {
    return '« $name » ($size) sera effacé de l\'appareil. Irréversible.';
  }

  @override
  String get dlOrphanDeleted => 'Fichier supprimé';

  @override
  String get dlOrphanDeleteFailed => 'Android a refusé la suppression';

  @override
  String get dlOrphanPlay => 'Lire';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get tmdbStatusOn => 'TMDB connecté : affiches, résumés et casting';

  @override
  String get tmdbStatusOff =>
      'Sans clé TMDB : pas d\'affiches ni de résumés en plus. L\'application fonctionne quand même.';

  @override
  String get tmdbPairReplace => 'Remplacer depuis mon téléphone';

  @override
  String get tmdbPairSetup => 'Configurer depuis mon téléphone';

  @override
  String get tmdbPairSub =>
      'Scanne le QR code et colle la clé depuis le téléphone';

  @override
  String get tmdbKeySection => 'Clé TMDB';

  @override
  String get tmdbKeySectionManual => 'Saisie à la télécommande';

  @override
  String get tmdbKeyHint => 'Colle ta clé ici…';

  @override
  String get tmdbKeyShow => 'Afficher';

  @override
  String get tmdbKeyHide => 'Masquer';

  @override
  String get tmdbKeySave => 'Enregistrer';

  @override
  String get tmdbKeyRemove => 'Retirer la clé';

  @override
  String get tmdbKeyManualEntry => 'Saisir à la télécommande';

  @override
  String get tmdbKeyConnected => 'TMDB connecté';

  @override
  String get tmdbKeyRemoved => 'Clé TMDB retirée';

  @override
  String get tmdbKeyRejected =>
      'TMDB refuse cette clé. Vérifie que tu as copié le jeton d\'accès en lecture (API Read Access Token).';

  @override
  String get tmdbKeyUnverified =>
      'Clé enregistrée. Impossible de la vérifier pour l\'instant (pas de réseau).';

  @override
  String get tmdbKeyChecking => 'Vérification…';

  @override
  String get tmdbHowTitle => 'Obtenir une clé (gratuit)';

  @override
  String get tmdbHowStep1 => 'Crée un compte sur themoviedb.org';

  @override
  String get tmdbHowStep2 => 'Ouvre Paramètres, puis API';

  @override
  String get tmdbHowStep3 =>
      'Copie le jeton d\'accès en lecture (API Read Access Token)';

  @override
  String get tmdbHowStep4 => 'Colle-le ci-dessous';

  @override
  String get tmdbSignup => 'Créer un compte TMDB';

  @override
  String get tmdbLogin => 'J\'ai déjà un compte';

  @override
  String get tmdbOptionsTitle => 'Options';

  @override
  String get tmdbVisualLangTitle => 'Langue des visuels';

  @override
  String tmdbVisualLangSub(String lang) {
    return '$lang : affiches, résumés et casting';
  }

  @override
  String get tmdbPostersFirstTitle => 'Affiches TMDB en priorité';

  @override
  String get tmdbPostersFirstOn =>
      'Le carrousel et les favoris prennent l\'affiche TMDB.';

  @override
  String get tmdbPostersFirstOff =>
      'Le carrousel et les favoris gardent l\'affiche de tes listes.';

  @override
  String get tmdbMemoryTitle => 'Données mémorisées';

  @override
  String get tmdbMemoryPosters => 'Affiches';

  @override
  String get tmdbMemoryPostersNone =>
      'Aucune affiche mémorisée pour l\'instant';

  @override
  String tmdbMemoryPostersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count affiches mémorisées',
      one: '1 affiche mémorisée',
    );
    return '$_temp0';
  }

  @override
  String get tmdbMemoryClear => 'Vider';

  @override
  String get tmdbMemoryPostersCleared =>
      'Affiches oubliées. Elles se rechargeront au fil de la navigation.';

  @override
  String get tmdbMemorySorting => 'Rangement automatique';

  @override
  String get tmdbMemorySortingNone =>
      'Rien à réapprendre : tes listes rangent déjà leurs titres';

  @override
  String tmdbMemorySortingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres rangés grâce à TMDB',
      one: '1 titre rangé grâce à TMDB',
    );
    return '$_temp0';
  }

  @override
  String get tmdbMemoryRelearn => 'Réapprendre';

  @override
  String get tmdbMemorySortingCleared =>
      'Rangement oublié. Il se refera en parcourant l\'accueil.';

  @override
  String get reloadAllTitle => 'Tout recharger ?';

  @override
  String reloadAllBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Les $count listes vont être retéléchargées depuis leurs serveurs. Cela peut prendre plusieurs minutes.',
      one:
          'La liste va être retéléchargée depuis son serveur. Cela peut prendre plusieurs minutes.',
    );
    return '$_temp0';
  }

  @override
  String reloadAllBodyRecent(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Les $count listes vont être retéléchargées depuis leurs serveurs.',
      one: 'La liste va être retéléchargée depuis son serveur.',
    );
    return '$_temp0\n\nDéjà à jour (moins de 24 h) : $names.\n\nCela peut prendre plusieurs minutes.';
  }

  @override
  String get reloadAllConfirm => 'Tout recharger';

  @override
  String get reloadAllProgressTitle => 'Rechargement en cours';

  @override
  String get reloadAllPreparing => 'Préparation…';

  @override
  String reloadAllStep(int index, int total, String label) {
    return 'Liste $index/$total — $label';
  }

  @override
  String get reloadAllTooltip => 'Recharger toutes les listes';

  @override
  String get reloadAllNoAccounts => 'Aucune liste à recharger';
}
