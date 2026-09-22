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
  String get terminalEtaMessage => 'Temps restant';

  @override
  String get terminalElapsedMessage => 'Temps écoulé';

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
  String get episode => 'Épisode';

  @override
  String get favoriteAdd => 'Ajouter aux favoris';

  @override
  String get favoriteRemove => 'Retirer des favoris';

  @override
  String get actionSheetPlay => 'Lire';

  @override
  String get actionSheetDownload => 'Télécharger en arrière-plan';

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
  String get accountsTitle => 'Gestion des Comptes';

  @override
  String get deleteAccountDialogTitle => 'Supprimer le compte ?';

  @override
  String get deleteAccountConfirm => 'Supprimer';

  @override
  String get accountActionEdit => 'Modifier';

  @override
  String get accountActionDelete => 'Supprimer';

  @override
  String get editAccountTitleAdd => 'Ajouter un compte';

  @override
  String get editAccountTitleEdit => 'Modifier le compte';

  @override
  String get editAccountNameLabel => 'Nom du compte (ex: Salon, Vacances...)';

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
  String get editAccountSaveButton => 'Enregistrer';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get backupTitle => 'Sauvegarde';

  @override
  String get optimizationTitle => 'Optimisation';

  @override
  String get regionFilterTitle => 'Langues et régions';

  @override
  String get regionHideSection => 'Contenu à masquer';

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
      'Tout régler depuis ton téléphone, même la télécommande';

  @override
  String get settingsSectionSources => 'Sources & comptes';

  @override
  String get settingsAccounts => 'Comptes IPTV';

  @override
  String get settingsAccountsSub =>
      'Tes abonnements, ce qu\'ils contiennent, les recharger';

  @override
  String get settingsTmdbKey => 'Affiches et infos TMDB';

  @override
  String get settingsTmdbKeySub => 'Affiches, résumés, casting — optionnel';

  @override
  String get settingsXmltv => 'Guide des chaînes';

  @override
  String get settingsXmltvSub => 'Programmes des chaînes de la TNT';

  @override
  String get settingsSectionDisplay => 'Affichage';

  @override
  String get settingsRegions => 'Langues et régions';

  @override
  String get settingsRegionsSub =>
      'Pistes retenues, contenu étranger à masquer';

  @override
  String get settingsTheme => 'Personnalisation';

  @override
  String get settingsThemeSub => 'Thème, couleurs, clair ou sombre';

  @override
  String get settingsOptimization => 'Optimisation';

  @override
  String get settingsOptimizationSub => 'La fluidité selon ton appareil';

  @override
  String get settingsSectionBackup => 'Sauvegarde & application';

  @override
  String get settingsBackup => 'Sauvegarde / Restauration';

  @override
  String get settingsBackupSub =>
      'Exporter/importer comptes, réglages, thèmes, favoris (.aether chiffré)';

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
  String get tmdbKeyRemoveTitle => 'Retirer la clé TMDB ?';

  @override
  String get tmdbKeyRemoveQuestion =>
      'Les affiches et infos TMDB ne se chargeront plus tant qu\'une clé n\'aura pas été saisie à nouveau.';

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
  String get reloadAllBackground => 'Continuer en arrière-plan';

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

  @override
  String get infoSectionTitle => 'Infos';

  @override
  String get infoGenre => 'Genre';

  @override
  String get infoDirector => 'Réalisateur';

  @override
  String get infoCreator => 'Créateur';

  @override
  String get infoOriginalTitle => 'Titre original';

  @override
  String get infoCountry => 'Pays';

  @override
  String get infoStudios => 'Studios';

  @override
  String get infoStatus => 'Statut';

  @override
  String get infoRuntime => 'Durée';

  @override
  String get infoEpisodeLength => 'Épisode';

  @override
  String get infoSeasons => 'Saisons';

  @override
  String get infoNextEpisode => 'Prochain épisode';

  @override
  String get infoNetwork => 'Diffusé par';

  @override
  String get infoBudget => 'Budget';

  @override
  String get infoRevenue => 'Recettes';

  @override
  String get infoTheatrical => 'Sortie salle';

  @override
  String get infoDigital => 'Sortie numérique';

  @override
  String infoSeasonsValue(int seasons, int episodes) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes épisodes',
      one: '1 épisode',
    );
    return '$seasons ($_temp0)';
  }

  @override
  String get perfProfileConfort => 'Complet';

  @override
  String get perfProfileEquilibre => 'Équilibré';

  @override
  String get perfProfilePerformance => 'Léger';

  @override
  String get autoProfileOk => 'Compris';

  @override
  String get capsTitle => 'Ce que ton appareil sait faire';

  @override
  String get capsSub => 'Décodeurs, écran, mémoire — mesurés, pas devinés';

  @override
  String get capsMeasure => 'Mesurer à nouveau';

  @override
  String get capsNever => 'Pas encore mesuré';

  @override
  String get capsDisplay => 'Écran';

  @override
  String get capsMemory => 'Mémoire';

  @override
  String get capsDecoders => 'Décodeurs vidéo';

  @override
  String get capsVerdict4k => 'Films 4K';

  @override
  String get capsHardware => 'matériel';

  @override
  String get capsSoftware => 'logiciel';

  @override
  String get capsNoDecoder => 'aucun décodeur';

  @override
  String get capsYes => 'Oui';

  @override
  String get capsNoDecoder4k => 'Non — aucun décodeur n\'accepte le 2160p';

  @override
  String get capsNoDisplay4k => 'Non — l\'écran affiche moins que 2160p';

  @override
  String get capsUnknown => 'Inconnu — mesure incomplète';

  @override
  String get capsLowRam => 'appareil à faible mémoire';

  @override
  String get refuse4kTitle => 'Cette version 4K ne peut pas être lue ici';

  @override
  String get refuse4kDecoder =>
      'Aucun décodeur de cet appareil n\'accepte une image de 3840×2160. Choisis une version FHD ou HD.';

  @override
  String refuse4kDisplay(int w, int h) {
    return 'L\'écran affiche $w×$h : la 4K serait décodée pour rien et risquerait de saccader. Choisis une version FHD ou HD.';
  }

  @override
  String get refuseOk => 'Compris';

  @override
  String autoProfileTitle(String name) {
    return 'Profil $name choisi pour cet appareil';
  }

  @override
  String autoProfileBody(String name, int ram, int cores) {
    return 'D\'après la mesure ($ram Mo de mémoire, $cores cœurs), l\'accueil est réglé sur le profil $name. Modifiable à tout moment dans Paramètres → Optimisation.';
  }

  @override
  String capsMeasuredAt(String date) {
    return 'Mesuré le $date';
  }

  @override
  String capsDisplayValue(int w, int h, int hz) {
    return '$w×$h à $hz Hz';
  }

  @override
  String capsMemoryValue(int total, int avail) {
    return '$total Mo au total, $avail Mo libres';
  }

  @override
  String capsDecoderValue(String name, String kind, int w, int h) {
    return '$name ($kind) — jusqu\'à $w×$h';
  }

  @override
  String get perfProfileConfortSub => 'Toutes les animations';

  @override
  String get perfProfileEquilibreSub => 'Hero fixe, rangées courtes';

  @override
  String get perfProfilePerformanceSub => 'Peu de mémoire';

  @override
  String get tmdbRowsProvidersTitle => 'Tendances Netflix, Disney+ et Prime';

  @override
  String get tmdbRowsProvidersSub =>
      'Ce qui marche en ce moment sur chaque plateforme en France, parmi tes listes';

  @override
  String rowProviderTrending(String name) {
    return 'Tendances $name';
  }

  @override
  String get perfDownloadsSection => 'Téléchargements';

  @override
  String get perfParallelDownloadsTitle => 'Transferts en même temps';

  @override
  String get taskStatusQueuedWhy =>
      'En attente : un transfert à la fois par abonnement';

  @override
  String get perfWifiOnlyTitle => 'Télécharger en Wi-Fi seulement';

  @override
  String get perfWifiOnlySub =>
      'Sur les données mobiles (ou un partage de connexion facturé), les transferts attendent et repartent seuls dès qu\'un Wi-Fi ou une connexion filaire revient.';

  @override
  String get taskStatusWaitWifi => 'En attente du Wi-Fi (réseau facturé)';

  @override
  String get taskStatusWaitNetwork => 'En attente du réseau';

  @override
  String get offlineBannerTitle =>
      'Hors ligne — seuls les fichiers téléchargés sont lisibles';

  @override
  String get offlineBannerRetry => 'Réessayer';

  @override
  String get offlineBootMessage =>
      'Pas de réseau pour charger tes listes. Tes fichiers téléchargés restent là ; l\'application reprendra d\'elle-même dès que la connexion reviendra.';

  @override
  String capsDisplayModesNote(int w, int h) {
    return 'L\'écran annonce jusqu\'à $w×$h. Android affiche l\'interface en plus petit ; la vidéo, elle, sort en natif.';
  }

  @override
  String get capsDisplayUiNote =>
      'Ce qu\'Android annonce ici décrit l\'interface, pas forcément la dalle : beaucoup de téléviseurs 4K affichent leurs menus en 1080p et la vidéo en 2160p. Seuls les décodeurs décident de la 4K.';

  @override
  String get perfPurgeNothing => 'Rien à récupérer — aucun fichier orphelin';

  @override
  String perfPurgeDone(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '🧹 $size libérés ($count fichiers)',
      one: '🧹 $size libérés ($count fichier)',
    );
    return '$_temp0';
  }

  @override
  String get perfResetTitle => 'Réinitialiser les réglages ?';

  @override
  String get perfResetQuestion =>
      'Tous les réglages d\'optimisation reviennent aux valeurs par défaut.';

  @override
  String get perfResetConfirm => 'Réinitialiser';

  @override
  String get perfResetDone => 'Réglages réinitialisés';

  @override
  String perfFreeMemoryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '💤 $count comptes secondaires déchargés de la mémoire',
      one: '💤 $count compte secondaire déchargé de la mémoire',
    );
    return '$_temp0';
  }

  @override
  String get perfFreeMemoryNothing => 'Rien à libérer (un seul compte chargé)';

  @override
  String get perfImageCacheCleared => '🧹 Cache images vidé';

  @override
  String get perfSectionProfiles => 'Profils';

  @override
  String get perfSectionHero => 'Bandeau d\'accueil';

  @override
  String get perfHeroSub =>
      'Empilement de cartes en tête de la home (coûteux sur box faible)';

  @override
  String get perfAutoRotateTitle => 'Rotation automatique';

  @override
  String get perfAutoRotateSub =>
      'Fait défiler le hero toutes les 6 s (swipe manuel toujours actif)';

  @override
  String get perfHeroCardsLabel => 'Cartes';

  @override
  String get perfSectionRows => 'Rangées de catégories';

  @override
  String get perfItemsLabel => 'Vignettes';

  @override
  String get perfItemsSub =>
      'Vignettes affichées par rangée avant la tuile « Voir tout » (les Favoris ne sont jamais tronqués).';

  @override
  String get perfSectionPlayback => 'Lecture';

  @override
  String get perfAutoNextTitle => 'Épisode suivant automatique';

  @override
  String get perfAutoNextSub =>
      'Enchaîne l\'épisode suivant en fin de lecture, après un décompte annulable. Un changement de saison demande toujours confirmation.';

  @override
  String get perfBufferLabel => 'Tampon de lecture';

  @override
  String get perfBufferSub =>
      'Secondes de vidéo gardées d\'avance. Monter aide sur un fournisseur qui bride — la lecture puise dans le tampon au lieu de s\'arrêter — mais tient d\'autant plus de flux en mémoire, ce qui compte sur une box. Le compteur « Blocages » de l\'encart Infos vidéo dit si le réglage sert à quelque chose. Prend effet à la lecture suivante.';

  @override
  String get perfSectionLists => 'Listes';

  @override
  String get perfKeepListsTitle => 'Garder toutes les listes en mémoire';

  @override
  String get perfKeepListsSub =>
      'Chaque compte reste chargé : la recherche couvre tous les comptes et le changement de liste est instantané. Demande plus de mémoire — à éteindre sur un Fire Stick ou une box qui en a peu.';

  @override
  String get perfUnloadAfterLabel => 'Décharger après';

  @override
  String get perfUnloadNever => 'Jamais';

  @override
  String perfMinutesShort(int count) {
    return '$count min';
  }

  @override
  String get perfUnloadSub =>
      'Minutes sans consulter une liste secondaire avant de la sortir de la mémoire. « Jamais » (0) équivaut à garder toutes les listes.';

  @override
  String get perfSectionMemory => 'Mémoire & usage';

  @override
  String get perfImageRamLabel => 'Mémoire des images';

  @override
  String get perfImageRamSub =>
      'Mémoire vive réservée aux images déjà affichées. À n\'ajuster que si la mémoire manque vraiment.';

  @override
  String get perfFreeMemoryButton =>
      'Libérer la mémoire des comptes secondaires';

  @override
  String get perfClearImageCacheButton => 'Vider le cache images';

  @override
  String get perfClearImageCacheNote =>
      'Les vignettes sont gardées sur le disque pour éviter de les re-télécharger. À vider si une affiche a changé côté fournisseur ou si le stockage sature.';

  @override
  String get perfSectionStorage => 'Stockage';

  @override
  String get perfStorageScanning => 'Analyse du stockage…';

  @override
  String get perfStorageNothing =>
      'Rien à récupérer : chaque fichier appartient à un compte existant.';

  @override
  String perfStorageReclaimable(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$size occupés par $count fichiers dont plus personne n\'a besoin : listes de comptes supprimés, et téléchargements interrompus qui ne peuvent plus reprendre.',
      one:
          '$size occupés par $count fichier dont plus personne n\'a besoin : listes de comptes supprimés, et téléchargements interrompus qui ne peuvent plus reprendre.',
    );
    return '$_temp0';
  }

  @override
  String get perfPurging => 'Nettoyage…';

  @override
  String get perfPurgeButton => 'Nettoyer les fichiers orphelins';

  @override
  String get perfUnitSeconds => ' s';

  @override
  String get perfUnitMegabytes => ' Mo';

  @override
  String get acctAddHowTitle => 'Comment ajouter une playlist ?';

  @override
  String get acctAddFromPhone => 'Depuis mon téléphone';

  @override
  String get acctAddFromPhoneSub =>
      'Recommandé — QR vers le panneau complet (ajout, édition, rechargement)';

  @override
  String get acctAddWithRemote => 'Avec la télécommande';

  @override
  String get acctAddWithRemoteSub => 'Saisie touche par touche';

  @override
  String acctDeleteBody(String label) {
    return '« $label » et ses identifiants seront effacés définitivement.';
  }

  @override
  String acctDeleteListGone(String size) {
    return 'La liste téléchargée part avec ($size libérés).';
  }

  @override
  String get acctDeleteNoList =>
      'Aucune liste téléchargée à effacer pour ce compte.';

  @override
  String get acctDeleteKept =>
      'Favoris, reprises de lecture et téléchargements terminés sont conservés.';

  @override
  String acctDeletedWithSize(String label, String size) {
    return '✅ « $label » supprimé — $size libérés';
  }

  @override
  String acctDeleted(String label) {
    return '✅ « $label » supprimé';
  }

  @override
  String get acctAdd => 'Ajouter';

  @override
  String get acctEmptyTitle => 'Aucun compte configuré';

  @override
  String get acctEmptySubTv =>
      'Scanne le QR code avec ton téléphone pour configurer ta playlist sans avoir à taper au D-pad.';

  @override
  String get acctEmptySubPhone =>
      'Ajoute une URL M3U complète ou un compte Xtream Codes pour commencer à streamer.';

  @override
  String get acctEmptyCtaTv => 'Configurer depuis mon téléphone';

  @override
  String get acctEmptyCtaPhone => 'Ajouter une playlist';

  @override
  String get acctMainAccount => 'COMPTE PRINCIPAL';

  @override
  String acctListsCount(int count) {
    return '$count listes';
  }

  @override
  String acctStatusInProgress(int loaded, int total, int inProgress) {
    return '$loaded/$total · $inProgress en cours…';
  }

  @override
  String acctStatusWithFailed(String base, int failed) {
    return '$base · $failed en échec';
  }

  @override
  String acctStatusFailed(int loaded, int total, int failed) {
    return '$loaded/$total · $failed en échec';
  }

  @override
  String acctStatusLoaded(int loaded, int total) {
    return '✓ $loaded/$total chargées';
  }

  @override
  String acctReloadedFor(String label) {
    return '✅ Playlist rechargée pour $label';
  }

  @override
  String commonFailedWith(String reason) {
    return '❌ Échec : $reason';
  }

  @override
  String get acctReloadTitle => 'Recharger ?';

  @override
  String acctReloadBody(String label, String age) {
    return 'La playlist de « $label » a été téléchargée il y a $age.\nRecharger quand même depuis le serveur ?';
  }

  @override
  String get acctReload => 'Recharger';

  @override
  String get acctDownloading => 'Téléchargement…';

  @override
  String get acctReloadPlaylist => 'Recharger la playlist';

  @override
  String get acctChipAvailable => 'DISPONIBLE';

  @override
  String get acctChipDownloading => 'TÉLÉCHARGEMENT…';

  @override
  String get acctChipLoading => 'CHARGEMENT…';

  @override
  String get acctChipError => 'ERREUR';

  @override
  String get acctChipNotLoaded => 'NON CHARGÉ';

  @override
  String get acctChipExpired => 'EXPIRÉE';

  @override
  String get acctChipExpiresToday => 'EXPIRE AUJOURD\'HUI';

  @override
  String acctChipExpiresIn(int days) {
    return 'EXPIRE DANS $days J';
  }

  @override
  String get acctCountFilms => 'Films';

  @override
  String get acctCountSeries => 'Séries';

  @override
  String get acctCountTv => 'Chaînes';

  @override
  String acctStartupTime(String seconds) {
    return 'départ $seconds s';
  }

  @override
  String get acctM3uSize => 'Taille M3U';

  @override
  String get acctCacheAge => 'Âge cache';

  @override
  String get acctNoCache => 'Aucun cache';

  @override
  String get acctAgeJustNow => 'à l\'instant';

  @override
  String acctAgeMinutes(int count) {
    return 'il y a $count min';
  }

  @override
  String acctAgeHours(int count) {
    return 'il y a $count h';
  }

  @override
  String acctAgeDays(int count) {
    return 'il y a $count j';
  }

  @override
  String get acctXtreamLoading => 'Lecture des infos Xtream…';

  @override
  String get acctXtreamUnavailable => 'Infos Xtream indisponibles';

  @override
  String get acctExpiration => 'Expiration';

  @override
  String get acctConnections => 'Connexions';

  @override
  String get acctExpiryUnknown => 'Inconnue';

  @override
  String acctExpiryPast(int days) {
    return 'Expirée ($days j)';
  }

  @override
  String get acctExpiryToday => 'Expire aujourd\'hui';

  @override
  String get acctExpiryTomorrow => 'Expire demain';

  @override
  String acctExpiryInDays(int days) {
    return 'Dans $days jours';
  }

  @override
  String acctAgeHoursMinutes(int hours, String minutes) {
    return '${hours}h$minutes';
  }

  @override
  String acctAgeMinutesShort(int count) {
    return '${count}min';
  }

  @override
  String get homeExitSearch => 'Quitter la recherche';

  @override
  String get homeSearchHint => 'Rechercher dans la playlist…';

  @override
  String get homeTabSeries => 'Séries';

  @override
  String get homeTabMovies => 'Films';

  @override
  String get homeTabTv => 'Chaînes';

  @override
  String get homeEmptyMovies => 'Aucun film';

  @override
  String get homeEmptySeries => 'Aucune série';

  @override
  String get homeEmptyTv => 'Aucune chaîne';

  @override
  String get homeEmptySub =>
      'Aucune de tes listes n\'en contient. Recharge une liste ou ajoute un compte.';

  @override
  String get homeEmptyCta => 'Gérer les comptes';

  @override
  String get homeSeeAll => 'Voir tout';

  @override
  String get homeResume => 'REPRENDRE';

  @override
  String get homeResumeChannel => 'REPRENDRE LA CHAÎNE';

  @override
  String get searchNoTitleFound => 'Aucun titre trouvé';

  @override
  String searchNoTitleSub(String query) {
    return 'Rien dans vos listes pour « $query ». Essaie un autre mot-clé ou vérifie l\'orthographe.';
  }

  @override
  String get searchKeepTyping => 'Continue à taper…';

  @override
  String searchKeepTypingSub(int count) {
    return 'Au moins $count lettres pour chercher un film ou une série. Les chaînes, elles, se cherchent dès la première lettre.';
  }

  @override
  String searchFromPerson(String name) {
    return 'De $name, dans tes listes';
  }

  @override
  String get searchOnTmdbMissing => 'Sur TMDB, absent de tes listes';

  @override
  String get searchNotAvailable => 'NON DISPO';

  @override
  String get searchTypeToSearch => 'Tapez pour chercher dans votre playlist';

  @override
  String get searchTypesLine => 'Films · Séries · Chaînes';

  @override
  String get searchRecent => 'Recherches récentes';

  @override
  String get searchClearHistoryTitle => 'Effacer l\'historique ?';

  @override
  String get searchClearHistoryOne => 'La dernière recherche sera supprimée.';

  @override
  String searchClearHistoryMany(int count) {
    return 'Les $count dernières recherches seront supprimées.';
  }

  @override
  String get searchClearConfirm => 'Effacer';

  @override
  String get searchHistoryCleared => 'Historique effacé';

  @override
  String get cardPlay => 'Lire';

  @override
  String cardResumeFrom(String position) {
    return 'Reprendre depuis $position';
  }

  @override
  String get cardPlayFromStart => 'Lire depuis le début';

  @override
  String get cardForgetResume => 'Oublier la reprise';

  @override
  String get cardForgetResumeTitle => 'Oublier la reprise ?';

  @override
  String get cardForgetResumeQuestion =>
      'La position de lecture de ce titre sera oubliée.';

  @override
  String get cardForgetResumeSeriesQuestion =>
      'Cette série sortira de « Reprendre ». L\'épisode en cours, lui, garde sa position dans sa fiche.';

  @override
  String get cardForgetConfirm => 'Oublier';

  @override
  String get cardResumeForgotten => 'Reprise oubliée';

  @override
  String get cardResumeForgottenSeries => 'Série retirée de « Reprendre »';

  @override
  String get cardChooseEpisode => 'Choisir un épisode';

  @override
  String get cardDetails => 'Voir les détails';

  @override
  String get castChannelsStereo => 'stéréo';

  @override
  String get castChannelsMono => 'mono';

  @override
  String castChannelsCount(int count) {
    return '$count canaux';
  }

  @override
  String get castAudioTrackFallback => 'Piste audio';

  @override
  String castAudioWarnPartial(String track) {
    return 'Le téléviseur ne décodera pas toutes les pistes de ce flux. L\'app va lui demander : $track. Si le son manque quand même, c\'est que le récepteur a gardé sa piste par défaut.';
  }

  @override
  String castAudioWarnSingle(String detail) {
    return 'Le son de ce flux est en $detail : le récepteur du téléviseur ne sait pas le décoder (image sans son). L\'app ne peut pas le convertir.';
  }

  @override
  String castAudioWarnNone(String detail) {
    return 'Aucune piste audio de ce flux n\'est décodable par le récepteur du téléviseur ($detail) : image sans son. Une autre version du même titre, en AAC, passerait.';
  }

  @override
  String get castReceiverNoTracks => 'aucune piste annoncée';

  @override
  String castReceiverNoAudio(int count) {
    return '$count piste(s), aucune audio';
  }

  @override
  String castReceiverAudioSummary(int count, String labels) {
    return '$count audio : $labels';
  }

  @override
  String get castNoWifi =>
      'Le téléphone n\'est pas sur un réseau Wi-Fi : le Chromecast ne peut pas venir chercher le fichier. Connecte-le au même réseau que la télé.';

  @override
  String get castNotStreamable =>
      'Cette adresse n\'est pas diffusable (ni http ni https).';

  @override
  String get castCannotVerify =>
      'Impossible de vérifier le flux depuis ce réseau. Réessaie dans un instant.';

  @override
  String get castTlsRefused =>
      'Le fournisseur utilise un certificat que le Chromecast refuse (l\'app, elle, l\'accepte). Ce flux ne peut pas être diffusé.';

  @override
  String get castUnreachable =>
      'Le serveur du fournisseur ne répond pas depuis ce réseau.';

  @override
  String get castNeedsAuth =>
      'Ce flux n\'est pas diffusable : le fournisseur exige une identification que le Chromecast ne peut pas transmettre.';

  @override
  String get castNotHls =>
      'Le fournisseur ne propose pas ce flux dans un format que le Chromecast sait lire (HLS).';

  @override
  String castHttpRefused(int code) {
    return 'Ce flux n\'est pas diffusable : le fournisseur refuse une requête sans le profil IPTV de l\'app (réponse HTTP $code), que le Chromecast ne peut pas imiter.';
  }

  @override
  String get castNoCors =>
      'Ce flux n\'est pas diffusable : le fournisseur n\'autorise pas la lecture depuis un navigateur (pas d\'en-tête CORS), et c\'est ainsi que le Chromecast lit le HLS.';

  @override
  String castNoticePlaying(String device) {
    return 'Diffusion sur $device';
  }

  @override
  String castNoticePaused(String device) {
    return 'En pause sur $device';
  }

  @override
  String get castIdleFinished => 'Lecture terminée sur le téléviseur.';

  @override
  String get castIdleError =>
      'Le téléviseur n\'a pas pu lire ce flux (format ou adresse refusés par le récepteur).';

  @override
  String get castIdleInterrupted => 'Diffusion interrompue par le téléviseur.';

  @override
  String get perrTimedOut => 'Le flux ne répond plus (délai dépassé).';

  @override
  String get perrConnectionFailed =>
      'Connexion au serveur impossible. Vérifie le réseau.';

  @override
  String get perrConnectionTimeout =>
      'Le serveur a mis trop de temps à répondre.';

  @override
  String get perrBadHttpStatus =>
      'Le serveur a refusé le flux (erreur HTTP). Vérifie le compte ou réessaie plus tard.';

  @override
  String get perrFileNotFound => 'Flux introuvable sur le serveur.';

  @override
  String get perrNoPermission => 'Accès au flux refusé.';

  @override
  String get perrCleartextNotPermitted =>
      'Connexion non chiffrée refusée par le système.';

  @override
  String get perrInvalidContentType =>
      'Le serveur ne renvoie pas une vidéo (type de contenu inattendu).';

  @override
  String get perrPositionOutOfRange => 'Position de lecture hors du flux.';

  @override
  String get perrNetwork => 'Erreur de lecture réseau.';

  @override
  String get perrBehindLiveWindow =>
      'Trop en retard sur le direct : reprise au direct.';

  @override
  String get perrPlayerTimeout => 'Le lecteur n\'a pas répondu à temps.';

  @override
  String get perrMalformed =>
      'Flux illisible (données corrompues ou inattendues).';

  @override
  String get perrUnsupportedFormat => 'Format de flux non pris en charge.';

  @override
  String get perrDecoderInit => 'Impossible d\'initialiser le décodeur vidéo.';

  @override
  String get perrDecoderReclaimed =>
      'Le système a repris le décodeur vidéo. Ferme les autres applications, puis relance la lecture.';

  @override
  String get perrDecodingFailed =>
      'Échec du décodage : le flux est peut-être abîmé.';

  @override
  String get perrExceedsCapabilities =>
      'Ce flux dépasse les capacités de l\'appareil (définition ou débit).';

  @override
  String get perrCodecUnsupported =>
      'Codec non pris en charge par cet appareil.';

  @override
  String get perrAudioOutput =>
      'Sortie audio indisponible (piste ou format audio non lisible).';

  @override
  String get perrRemote => 'Erreur du lecteur distant.';

  @override
  String get perrUnexpected => 'Le lecteur a rencontré une erreur inattendue.';

  @override
  String get perrDrm => 'Contenu protégé (DRM) non lisible.';

  @override
  String get perrDecodeVideo => 'Échec du décodage vidéo.';

  @override
  String get perrCannotPlay => 'Lecture impossible.';

  @override
  String get relayBatteryPluggedOk =>
      'Le téléphone est branché, parfait pour un film.';

  @override
  String get relayBatteryPlugIfYouCan =>
      'Branche le téléphone si tu peux : la conversion consomme beaucoup de batterie.';

  @override
  String relayBatteryLow(int percent) {
    return 'Batterie à $percent % — branche le téléphone, la diffusion en dépend.';
  }

  @override
  String relayBatteryMid(int percent) {
    return 'Batterie à $percent %. Branche le téléphone si tu peux, la conversion consomme beaucoup de batterie.';
  }

  @override
  String get relayScreenOffOk =>
      'Tu peux éteindre l\'écran : la diffusion continue en arrière-plan.';

  @override
  String get relayDeviceFallback => 'la télé';

  @override
  String relayConsentWhat(String device) {
    return 'Ce téléviseur ne lit pas le son de ce film. Le téléphone peut l\'adapter pendant la diffusion pour $device.';
  }

  @override
  String get relayConsentConfirm => 'Adapter et diffuser';

  @override
  String get playerLastEpisode => 'Dernier épisode disponible.';

  @override
  String playerAudioTrackSwitched(String track) {
    return 'Piste audio incompatible — bascule sur $track';
  }

  @override
  String get playerNoAudioTrack =>
      'Aucune piste audio lisible sur ce fichier — lecture sans son';

  @override
  String playerReconnecting(int attempt, int max) {
    return 'Reconnexion dans 5 s… ($attempt/$max)';
  }

  @override
  String get playerRetry => 'Réessayer';

  @override
  String get playerBuffering => 'Mise en mémoire tampon…';

  @override
  String get castOverlayBack => 'Retour (la diffusion continue)';

  @override
  String castOverlayCastingOn(String device) {
    return 'DIFFUSION SUR $device';
  }

  @override
  String get castOverlayStarting => 'Démarrage sur le téléviseur…';

  @override
  String castOverlayPlayingAt(String position) {
    return 'En lecture · $position';
  }

  @override
  String get castOverlayLoading => 'Chargement sur le téléviseur…';

  @override
  String get castOverlayBack30 => 'Reculer de 30 s';

  @override
  String get castOverlayPause => 'Pause';

  @override
  String get castOverlayPlay => 'Lecture';

  @override
  String get castOverlayForward30 => 'Avancer de 30 s';

  @override
  String castOverlayReceiver(String detail) {
    return 'Récepteur · $detail';
  }

  @override
  String castOverlayCastTitle(String title) {
    return 'Diffuser « $title »';
  }

  @override
  String get castOverlayResync => 'Resynchroniser l\'image et le son';

  @override
  String get castOverlayResumeHere => 'Reprendre sur le téléphone';

  @override
  String get castOverlaySoundConverted => 'Son entièrement converti';

  @override
  String get castOverlaySoundConverting => 'Conversion du son en cours';

  @override
  String get castOverlayTvPlaysWhileConverting =>
      'Le téléviseur lit pendant la conversion. Garder l\'application ouverte.';

  @override
  String castOverlayPreparingFor(String device) {
    return 'PRÉPARATION POUR $device';
  }

  @override
  String get castOverlayCancelConversion => 'Annuler la conversion';

  @override
  String get castSheetNotCastable => 'Ce flux n\'est pas diffusable.';

  @override
  String castSheetOnDevice(String device) {
    return 'Sur $device';
  }

  @override
  String get castSheetTitle => 'Diffuser sur…';

  @override
  String get castSheetSearching => 'Recherche des appareils sur le réseau…';

  @override
  String castSheetChecking(String device) {
    return 'Vérification du flux pour $device…';
  }

  @override
  String get castSheetChooseOther => 'Choisir un autre appareil';

  @override
  String get castSheetConvertSound => 'Convertir le son sur le téléphone';

  @override
  String get castSheetConvertSoundSub =>
      'Voir ce que ça implique avant de lancer';

  @override
  String get castSheetCastAnyway => 'Diffuser quand même';

  @override
  String castSheetCastAnywaySub(String device) {
    return 'Sur $device — image sans son';
  }

  @override
  String get castSheetStop => 'Arrêter la diffusion';

  @override
  String castSheetStopSub(String device) {
    return 'En cours sur $device';
  }

  @override
  String get castSheetNothingFound =>
      'Aucun Chromecast trouvé. Le téléphone doit être sur le même WiFi que le téléviseur, hors réseau invité.';

  @override
  String get castSheetSearchAgain => 'Rechercher à nouveau';

  @override
  String get tracksNoAudio => 'Aucune piste audio détectée';

  @override
  String get tracksNoSubtitles => 'Aucun sous-titre détecté';

  @override
  String get tracksDisabled => 'Désactivés';

  @override
  String get tracksDisableFailed => 'Impossible de couper les sous-titres.';

  @override
  String get tracksTrackFailed => 'Cette piste n\'a pas pu être activée.';

  @override
  String get tracksResetFailed => 'Le retour à l\'automatique n\'a pas abouti.';

  @override
  String get tracksMemorySubOff => 'Coupés pour les prochains titres aussi';

  @override
  String tracksMemoryAudio(String lang) {
    return '$lang pour les prochains titres aussi';
  }

  @override
  String get tracksMemoryForget => 'Revenir à l\'automatique';

  @override
  String get settingsTracks => 'Langues des pistes';

  @override
  String get settingsTracksAuto =>
      'Automatique : chaque titre choisit son audio et ses sous-titres';

  @override
  String settingsTracksAudioLang(String lang) {
    return 'Audio : $lang';
  }

  @override
  String get settingsTracksSubsOff => 'Sous-titres : coupés';

  @override
  String get settingsTracksResetTitle => 'Revenir à l\'automatique ?';

  @override
  String get settingsTracksResetQuestion =>
      'Les prochains titres choisiront eux-mêmes leur langue audio et leurs sous-titres.';

  @override
  String get settingsTracksResetConfirm => 'Revenir à l\'automatique';

  @override
  String get settingsTracksResetDone => 'Pistes automatiques rétablies';

  @override
  String get langFrench => 'Français';

  @override
  String get langEnglish => 'Anglais';

  @override
  String get langSpanish => 'Espagnol';

  @override
  String get langGerman => 'Allemand';

  @override
  String get langItalian => 'Italien';

  @override
  String get langPortuguese => 'Portugais';

  @override
  String get langArabic => 'Arabe';

  @override
  String get langRussian => 'Russe';

  @override
  String get langDutch => 'Néerlandais';

  @override
  String get langJapanese => 'Japonais';

  @override
  String get langChinese => 'Chinois';

  @override
  String get langKorean => 'Coréen';

  @override
  String get langTurkish => 'Turc';

  @override
  String get langPolish => 'Polonais';

  @override
  String get statsDecoding => 'Décodage';

  @override
  String statsHardwareWith(String decoder) {
    return 'matériel · $decoder';
  }

  @override
  String get statsHardware => 'matériel';

  @override
  String get statsResolution => 'Résolution';

  @override
  String statsAnnouncedOversold(String announced) {
    return '$announced — la liste SURVEND';
  }

  @override
  String statsAnnouncedBetter(String announced) {
    return '$announced · mieux que promis';
  }

  @override
  String get statsYes => 'oui';

  @override
  String get statsNo => 'non';

  @override
  String get statsDropped => 'Sautées';

  @override
  String get statsBitrate => 'Débit';

  @override
  String get statsNetwork => 'Réseau';

  @override
  String get statsTransferred => 'Transféré';

  @override
  String get statsStartup => 'Démarrage';

  @override
  String get statsChannelsStereo => 'stéréo';

  @override
  String get statsChannelsMono => 'mono';

  @override
  String statsChannelsCount(int count) {
    return '$count canaux';
  }

  @override
  String get statsStallsNone => 'aucun';

  @override
  String statsStallsWithTime(int count, int seconds) {
    return '$count (${seconds}s au total)';
  }

  @override
  String get nextEpLoading => 'Chargement de l\'épisode suivant…';

  @override
  String get nextEpTitle => 'ÉPISODE SUIVANT';

  @override
  String get nextEpPlay => 'Lire';

  @override
  String get nextEpSeasonEnd => 'FIN DE LA SAISON';

  @override
  String nextEpGoToSeason(int season) {
    return 'Passer à la saison $season ?';
  }

  @override
  String get nextEpGoToNextSeason => 'Passer à la saison suivante ?';

  @override
  String get nextEpBackToDetails => 'Retour à la fiche';

  @override
  String get nextEpSeriesOver => 'SÉRIE TERMINÉE';

  @override
  String get nextEpSeriesOverSub =>
      'Vous avez vu le dernier épisode disponible.';

  @override
  String get ctrlCast => 'Diffuser sur un Chromecast';

  @override
  String get ctrlPip => 'Réduire en fenêtre';

  @override
  String get ctrlNextEpisode => 'Épisode suivant';

  @override
  String get ctrlBadgeMovie => 'FILM';

  @override
  String get ctrlBadgeSeries => 'SÉRIE';

  @override
  String get ctrlUnlock => 'Déverrouiller';

  @override
  String get optVideoInfo => 'Infos vidéo';

  @override
  String get fitContainSub => 'Image entière · bandes noires possibles';

  @override
  String get fitCoverSub => 'Efface les bandes noires · rogne les bords';

  @override
  String get fitFill => 'Plein écran';

  @override
  String get fitFillSub => 'Remplit tout · image légèrement déformée';

  @override
  String get ctrlCastActive => 'Diffusion en cours';

  @override
  String get ctrlLock => 'Verrouiller';

  @override
  String get ctrlBadgeLive => 'DIRECT';

  @override
  String get ctrlBadgeReplay => 'REPLAY';

  @override
  String get optBackToVideo => 'Revenir à la vidéo';

  @override
  String get sheetClose => 'Fermer';

  @override
  String get bootSlowHint =>
      'Le chargement est plus long que d\'habitude. Tu peux entrer dans l\'application : les listes finissent de se charger en arrière-plan.';

  @override
  String get bootContinueAnyway => 'Entrer sans attendre';

  @override
  String get bootStalledBody =>
      'Le chargement de la liste principale n\'avance plus. Il continue en arrière-plan : réessaie dans un instant, ou vérifie le compte.';

  @override
  String get playlistNoTitles =>
      'Cette liste ne contient aucun titre. Vérifie le compte, ou réessaie plus tard.';

  @override
  String get sheetCloseSub => 'Referme sans rien changer';

  @override
  String get optBackToVideoSub => 'Ferme ce panneau, la lecture continue';

  @override
  String get optSpeedTitle => 'Vitesse';

  @override
  String get optFitTitle => 'Format d\'image';

  @override
  String get castSheetDeviceFallback => 'le téléviseur';

  @override
  String get statsDecodingPending => 'en cours…';

  @override
  String get statsSoftware => 'LOGICIEL';

  @override
  String get statsOutput => 'Sortie';

  @override
  String get statsCodec => 'Codec';

  @override
  String get statsHdr => 'HDR';

  @override
  String get statsFps => 'Images/s';

  @override
  String get statsLost => 'Perdues';

  @override
  String get statsRendered => 'Rendu';

  @override
  String get statsBuffer => 'Tampon';

  @override
  String get statsAudio => 'Audio';

  @override
  String get statsStalls => 'Blocages';

  @override
  String statsAnnouncedOk(String announced) {
    return '$announced · conforme';
  }

  @override
  String statsRenderedValue(String fps) {
    return '$fps img/s';
  }

  @override
  String statsRenderedVsAnnounced(String fps, String announced) {
    return '$fps img/s (annoncé $announced)';
  }

  @override
  String statsSecondsValue(String value) {
    return '$value s';
  }

  @override
  String get fitOriginal => 'Original';

  @override
  String get fitZoom => 'Zoom';

  @override
  String playerRecovering(int attempt, int max) {
    return 'Reprise de la lecture… ($attempt/$max)';
  }

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Appliquer';

  @override
  String get commonApplying => 'Application…';

  @override
  String get bkPasswordTitle => 'Mot de passe de chiffrement';

  @override
  String get bkPasswordHelp =>
      'Choisis un mot de passe — il sera demandé pour restaurer la sauvegarde.';

  @override
  String get bkPasswordLabel => 'Mot de passe';

  @override
  String get bkPasswordConfirmLabel => 'Confirmer';

  @override
  String get bkPasswordEmpty => 'Le mot de passe ne peut pas être vide.';

  @override
  String get bkPasswordTooShort => 'Au moins 6 caractères.';

  @override
  String get bkPasswordMismatch => 'Les deux mots de passe diffèrent.';

  @override
  String get bkSave => 'Sauvegarder';

  @override
  String get bkCreated => 'Sauvegarde créée';

  @override
  String get bkCreateTitle => 'Créer une sauvegarde';

  @override
  String get bkCreateSub =>
      'Chiffre tes comptes, clés, thèmes, réglages, favoris et progression dans un fichier .aether.';

  @override
  String get bkEncrypting => 'Chiffrement en cours…';

  @override
  String get bkRestoreTitle => 'Restaurer une sauvegarde';

  @override
  String get bkRestoreSub =>
      'Sélectionne un fichier .aether, saisis ton mot de passe, vérifie le résumé, applique.';

  @override
  String get bkRestoring => 'Restauration en cours…';

  @override
  String get bkImportFile => 'Importer un fichier .aether';

  @override
  String get bkHowTitle => 'Comment ça marche';

  @override
  String get bkHowBody =>
      '• Fichier `.aether` chiffré AES-256-GCM + PBKDF2 (100k itérations).\n• Mot de passe choisi par toi — l\'app ne le stocke nulle part.\n• Stockage : Download/AetherStream/ (survit à un uninstall).\n• Contenu : comptes IPTV, clés TMDB et sous-titres, thèmes, réglages, favoris, progression.\n• Exclus : téléchargements (trop lourds), historique de recherche.\n• L\'import écrase entièrement la config actuelle (action irréversible).';

  @override
  String get bkRestorePasswordTitle => 'Mot de passe de la sauvegarde';

  @override
  String get bkDecrypt => 'Déchiffrer';

  @override
  String get bkConfirmRestoreTitle => 'Confirmer la restauration';

  @override
  String get bkConfirmRestoreBody =>
      'Tout l\'état actuel (comptes, clé TMDB, thème, favoris, progression de lecture) sera ÉCRASÉ par cette sauvegarde.\n\nAction irréversible. Continuer ?';

  @override
  String get bkRestore => 'Restaurer';

  @override
  String get bkRestoreDone => 'Restauration réussie';

  @override
  String get bkRestoreDoneSub =>
      'Les playlists IPTV seront re-téléchargées au prochain démarrage.';

  @override
  String get regionApplied => '✅ Filtre appliqué — catalogue rechargé';

  @override
  String get regionHelp =>
      'Coche les langues/régions à MASQUER du catalogue. Le contenu français (|FR|), québécois et VOSTFR est toujours conservé.';

  @override
  String get regionApplying => 'Application du filtre…';

  @override
  String get regionApplyingSub =>
      'Le catalogue est ré-analysé. Cela peut prendre quelques secondes.';

  @override
  String get regionHidden => 'Masqué';

  @override
  String get regionVisible => 'Visible';

  @override
  String get bkExportLocation =>
      'Disponible dans :\n/storage/emulated/0/Download/AetherStream/\n\nCopie ce fichier sur Drive, ton PC, ou un autre appareil pour le restaurer plus tard. N\'oublie pas le mot de passe — il n\'est nulle part stocké.';

  @override
  String get themeResetTitle => 'Réinitialiser le thème ?';

  @override
  String get themeResetQuestion =>
      'Toutes les couleurs et tous les effets reviennent aux valeurs par défaut.';

  @override
  String get themeSectionPresets => 'Thèmes prêts à l\'emploi';

  @override
  String get themeSectionColors => 'Couleurs';

  @override
  String get themeColorPrimary => 'Principale';

  @override
  String get themeColorAccent => 'Accent';

  @override
  String get themeColorTertiary => 'Tertiaire';

  @override
  String get themeSectionStateColors => 'Couleurs d\'état';

  @override
  String get themeColorFavorite => 'Favori ❤';

  @override
  String get themeColorWarning => 'Reprise / Alerte';

  @override
  String get themeColorError => 'Erreur';

  @override
  String get themeColorSuccess => 'Succès';

  @override
  String get themeSectionEffects => 'Effets';

  @override
  String get themeGlow => 'Halo lumineux';

  @override
  String get themeRadius => 'Arrondis';

  @override
  String get themeSectionMode => 'Mode';

  @override
  String get themeSectionPreview => 'Aperçu';

  @override
  String get themeModeDark => 'Sombre';

  @override
  String get themeModeLight => 'Clair';

  @override
  String get themeModeSystem => 'Système';

  @override
  String get themePreviewPlay => '▶  Lire';

  @override
  String get xmltvUpdated => '✅ Guide des chaînes mis à jour';

  @override
  String get xmltvUpdateUnavailable =>
      'Le guide des chaînes n\'a pas pu être mis à jour. Réessaie plus tard.';

  @override
  String xmltvUpdateFailed(String reason) {
    return '❌ Échec mise à jour : $reason';
  }

  @override
  String get xmltvNeverLoaded => 'Jamais chargé';

  @override
  String get xmltvJustNow => 'À l\'instant';

  @override
  String xmltvChannelsAndAge(int count, String age) {
    return '$count chaînes · $age';
  }

  @override
  String get xmltvDownloading => 'Téléchargement en cours…';

  @override
  String get xmltvForceUpdate => 'Forcer la mise à jour';

  @override
  String get xmltvHowBody =>
      '• Source publique : xmltvfr.fr (TNT France)\n• Couvre les principales chaînes françaises (TF1, France 2, M6, ARTE…)\n• Utilisé pour le bloc « En cours / Ensuite » et la grille replay';

  @override
  String visualLangApplied(String language) {
    return 'Visuels en $language — les affiches déjà affichées gardent leur langue jusqu\'au prochain rechargement.';
  }

  @override
  String get visualLangUiStaysFrench =>
      'Affiches, images de fond et textes venus de TMDB. L\'interface de l\'application suit la langue de l\'appareil.';

  @override
  String get visualLangNote =>
      'Une affiche fournie par votre liste IPTV n\'est jamais remplacée : ce choix ne s\'applique qu\'aux visuels que l\'application va chercher elle-même.';

  @override
  String get aboutChecking => '🔍 Vérification des mises à jour…';

  @override
  String get aboutUpToDate => 'Vous êtes à jour.';

  @override
  String aboutCheckFailed(String reason) {
    return '⚠️ Vérification impossible : $reason';
  }

  @override
  String get aboutTagline =>
      'Client IPTV Android — multi-comptes, EPG, replay, TMDB.';

  @override
  String get aboutCheckingShort => 'Vérification…';

  @override
  String get aboutCheckUpdates => 'Vérifier les mises à jour';

  @override
  String get consoleNoNetwork =>
      'Réseau local introuvable. Connecte la TV au Wi-Fi ou à l\'Ethernet.';

  @override
  String consoleStartFailed(String reason) {
    return 'Impossible de démarrer le serveur local : $reason';
  }

  @override
  String get consoleOpenAddress =>
      'Ouvre cette adresse dans un navigateur\nsur un PC ou un téléphone du même réseau :';

  @override
  String get consoleAddressCopied => 'Adresse copiée';

  @override
  String get consoleBackgroundNote =>
      'Le serveur reste actif en arrière-plan tant que tu utilises la télécommande, même après avoir quitté cet écran. Arrête-le ici quand tu as fini (sinon il se ferme après 30 min sans utilisation).';

  @override
  String get consoleStopServer => 'Arrêter le serveur';

  @override
  String get consoleActiveBanner =>
      'Console web ouverte : l\'app est pilotable depuis le réseau local';

  @override
  String get failNotLoaded => 'NON CHARGÉ';

  @override
  String get failNetwork => 'ÉCHEC RÉSEAU';

  @override
  String get failPanelBusy => 'PANEL SATURÉ';

  @override
  String get failIncomplete => 'LISTE INCOMPLÈTE';

  @override
  String get failParse => 'ANALYSE ÉCHOUÉE';

  @override
  String get failNoData => 'AUCUNE DONNÉE';

  @override
  String get failExplainNever => 'Cette liste n\'a pas encore été chargée.';

  @override
  String get failExplainUnloaded =>
      'Mémoire libérée ; la liste revient dès qu\'on en a besoin.';

  @override
  String get failExplainDeferred =>
      'Mise à jour reportée : cette liste sera reprise.';

  @override
  String get failExplainPanelBusy =>
      'Le fournisseur a refusé : trop de connexions simultanées.';

  @override
  String get failExplainIncomplete =>
      'Le catalogue est arrivé incomplet ; l\'ancien a été conservé.';

  @override
  String get failExplainParse => 'La liste n\'a pas pu être analysée.';

  @override
  String get failExplainCacheGone => 'Le cache analysé est illisible.';

  @override
  String get failExplainNoSource => 'Aucune donnée en cache pour cette liste.';

  @override
  String reloadBatchAllOk(int count) {
    return '✅ $count liste(s) rechargée(s)';
  }

  @override
  String reloadBatchAllFailed(String names) {
    return '❌ Aucune liste rechargée — $names';
  }

  @override
  String reloadBatchMixed(int ok, int failed, String names) {
    return '⚠️ $ok rechargée(s), $failed en échec : $names';
  }

  @override
  String get reloadDownloadFailed =>
      'Téléchargement impossible (vérifie l\'URL ou la connexion).';

  @override
  String get playlistNotAList =>
      'Le serveur n\'a pas renvoyé de liste exploitable. Vérifie l\'adresse de la playlist.';

  @override
  String get reloadParseFailed => 'L\'analyse de la liste a échoué.';

  @override
  String get bkPartTmdbKey => 'clé TMDB';

  @override
  String get bkPartTheme => 'thème';

  @override
  String get bkPartSubtitleKey => 'clé des sous-titres en ligne';

  @override
  String get bkPartPlayerSettings => 'réglages du lecteur';

  @override
  String get bkPartTrackMemory => 'langues des pistes';

  @override
  String bkPartHiddenRegions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count langues masquées',
      one: '1 langue masquée',
    );
    return '$_temp0';
  }

  @override
  String get bkPasswordEmptyError => 'Le mot de passe ne peut pas être vide.';

  @override
  String get bkNewerVersion =>
      'Sauvegarde créée par une version plus récente de l\'app ; mise à jour nécessaire.';

  @override
  String get bkWrongPassword =>
      'Mot de passe incorrect, ou fichier de sauvegarde altéré.';

  @override
  String get bkNoReadableAccount =>
      'Aucun compte de cette sauvegarde n\'a pu être lu : rien n\'a été modifié.';

  @override
  String get castDiscoveryFailed =>
      'Recherche impossible sur ce réseau. Le téléphone doit être sur le même WiFi que le téléviseur, hors réseau invité.';

  @override
  String castDeviceNotResponding(String device) {
    return '$device ne répond pas. Vérifie qu\'il est allumé et sur le même réseau.';
  }

  @override
  String castConnectFailed(String device) {
    return 'Connexion à $device impossible.';
  }

  @override
  String get castStreamRefused => 'Le téléviseur n\'a pas accepté ce flux.';

  @override
  String get castConnectionLost => 'Connexion au téléviseur perdue.';

  @override
  String get relayNoNetworkAddress =>
      'Aucune adresse réseau : le téléviseur ne pourrait pas joindre le téléphone.';

  @override
  String get relayStartFailed => 'La conversion n\'a pas pu démarrer.';

  @override
  String get relayOpenFailed =>
      'Impossible d\'ouvrir le relais sur le réseau local.';

  @override
  String get relayTooSlow =>
      'Le début du film n\'est pas arrivé à temps : la source est trop lente pour être convertie.';

  @override
  String get dlQueued => 'En attente…';

  @override
  String get dlFinalizing => 'Finalisation…';

  @override
  String dlActiveCount(int count) {
    return '$count téléchargements';
  }

  @override
  String updGithubHttp(int code) {
    return 'GitHub a répondu HTTP $code.';
  }

  @override
  String updNoApk(String tag) {
    return 'La dernière release ($tag) ne contient pas d\'APK.';
  }

  @override
  String get updTimeout => 'GitHub n\'a pas répondu à temps.';

  @override
  String get updUnreachable =>
      'Impossible de joindre GitHub. Vérifie la connexion.';

  @override
  String get updInstallDenied => 'Permission d\'installation refusée';

  @override
  String updNoApkForDevice(String tag) {
    return 'La dernière release ($tag) n\'a pas de version pour cet appareil.';
  }

  @override
  String get updUnverifiable =>
      'Cette mise à jour ne peut pas être vérifiée : elle n\'a pas été installée.';

  @override
  String get updCorrupted => 'La mise à jour téléchargée est abîmée. Réessaie.';

  @override
  String get failOnDisk => 'SUR DISQUE';

  @override
  String get failWaiting => 'EN ATTENTE';

  @override
  String get failCacheGone => 'CACHE PERDU';

  @override
  String get failBadAccount => 'COMPTE INVALIDE';

  @override
  String get failExplainNetwork => 'Serveur injoignable.';

  @override
  String get failExplainBadAccount => 'Configuration du compte invalide.';

  @override
  String bkPartAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: '1 compte',
    );
    return '$_temp0';
  }

  @override
  String get bkPartOptimization => 'optimisation';

  @override
  String bkPartFavorites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favoris',
      one: '1 favori',
    );
    return '$_temp0';
  }

  @override
  String bkPartProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count progressions',
      one: '1 progression',
    );
    return '$_temp0';
  }

  @override
  String get bkEmpty => 'Sauvegarde vide';

  @override
  String get relayFormatFailed =>
      'La conversion a échoué : le téléphone ne sait pas relire ce format.';

  @override
  String get dlFilterAll => 'Tout';

  @override
  String get dlFilterActive => 'En cours';

  @override
  String get dlFilterCompleted => 'Terminés';

  @override
  String get dlFilterErrors => 'Erreurs';

  @override
  String get dlSearchHint => 'Rechercher un téléchargement';

  @override
  String get dlSearchOpen => 'Rechercher';

  @override
  String get dlSearchClose => 'Fermer la recherche';

  @override
  String get dlEmptyHint =>
      'Lance un téléchargement depuis la fiche d\'un film ou d\'une série — il apparaîtra ici avec sa progression.';

  @override
  String get dlNoSearchResult =>
      'Aucun téléchargement ne correspond à cette recherche.';

  @override
  String dlNoneInFilter(String filter) {
    return 'Aucun téléchargement dans « $filter ».';
  }

  @override
  String get dlStopTitle => 'Arrêter le téléchargement ?';

  @override
  String get dlStopBody =>
      'Ce qui est déjà téléchargé est conservé : tu pourras reprendre là où ça s\'est arrêté.';

  @override
  String get dlStop => 'Arrêter';

  @override
  String get dlActionPlay => 'Lire';

  @override
  String get dlActionMonitor => 'Voir la progression';

  @override
  String get dlActionCancel => 'Arrêter le téléchargement';

  @override
  String get dlActionDelete => 'Supprimer';

  @override
  String dlRetriedTimes(int count) {
    return 'relancé ×$count';
  }

  @override
  String get dlAlreadyDownloaded => 'Déjà téléchargé';

  @override
  String get dlSee => 'Voir';

  @override
  String get dlStorageDenied =>
      'Permission de stockage refusée : le téléchargement ne peut pas démarrer.';

  @override
  String get dlOpenSettings => 'Ouvrir les réglages';

  @override
  String get bootFailedTitle => 'Démarrage interrompu';

  @override
  String get bootFailedBody =>
      'L\'application n\'a pas réussi à charger ta playlist.';

  @override
  String get bootCheckAccounts => 'Vérifier les comptes';

  @override
  String get bootNoAccountTitle => 'Aucun compte configuré';

  @override
  String get bootNoAccountTv =>
      'Scanne un QR code avec ton téléphone pour gérer tes playlists sans avoir à taper à la télécommande.';

  @override
  String get bootNoAccountPhone => 'Ajoute un compte pour commencer.';

  @override
  String get bootConfigureFromPhone => 'Configurer depuis mon téléphone';

  @override
  String get bootConfigureAccounts => 'Configurer les comptes';

  @override
  String get bootRestoreBackup => 'Restaurer une sauvegarde';

  @override
  String get onbPlaylistSaved => '✅ Playlist enregistrée';

  @override
  String get onbTmdbSaved => '✅ Clé TMDB enregistrée';

  @override
  String get onbHasBackup => 'J\'ai déjà une sauvegarde (.aether)';

  @override
  String get onbAddPlaylistTitle => 'Ajoute une playlist';

  @override
  String get onbAddPlaylistBody =>
      'Va dans ⚙️ Paramètres → Comptes IPTV pour saisir une URL M3U complète OU un compte Xtream Codes (serveur + identifiants).';

  @override
  String get onbTmdbTitle => 'Affiches et synopsis (optionnel)';

  @override
  String get onbTmdbBody =>
      'Génère un Bearer Token TMDB gratuit sur themoviedb.org et colle-le dans Paramètres → Clé API TMDB pour enrichir tes films et séries.';

  @override
  String get onbCardMenuTitle => 'Le menu ⋯ des vignettes';

  @override
  String get onbCardMenuBody =>
      'Appuie longuement sur une affiche — ou touche le ⋯ en haut à gauche — pour Lire, Reprendre, ajouter aux favoris, télécharger ou oublier une reprise, sans ouvrir la fiche.';

  @override
  String get onbWelcomeTitle => 'Bienvenue sur AetherStream';

  @override
  String get onbWelcomeBody =>
      'Client IPTV multi-comptes pour regarder films, séries et chaînes en direct depuis vos abonnements.';

  @override
  String get onbConfigureFromPhone => 'Configure depuis ton téléphone';

  @override
  String get onbQrBody =>
      'Scanne ce QR code : tu pourras ajouter ta playlist, ta clé TMDB et régler le reste depuis ton navigateur — la saisie au D-pad serait longue et fastidieuse.';

  @override
  String get actorNotFound => 'Erreur : fiche introuvable sur TMDB.';

  @override
  String get actorFilmographyDirecting => 'Filmographie (Réalisation)';

  @override
  String get actorFilmographyRoles => 'Filmographie (Rôles)';

  @override
  String get actorDirector => 'Réalisateur';

  @override
  String actorRole(String character) {
    return 'Rôle : $character';
  }

  @override
  String detActorNotFound(String name) {
    return 'TMDB n\'a pas trouvé de fiche pour $name.';
  }

  @override
  String get detTmdbPitch =>
      'Affiches, synopsis et casting. Config rapide au QR depuis ton mobile.';

  @override
  String detSaga(String name) {
    return 'Saga : $name';
  }

  @override
  String get detSameSaga => 'Même saga';

  @override
  String get detSeasons => 'Saisons';

  @override
  String detSeasonsCountOne(int seasons, int episodes) {
    return '$seasons saison · $episodes épisodes';
  }

  @override
  String detSeasonsCountMany(int seasons, int episodes) {
    return '$seasons saisons · $episodes épisodes';
  }

  @override
  String get detLoadingEpisodes => 'Chargement des épisodes…';

  @override
  String detEpisodesError(String reason) {
    return 'Épisodes non chargés — $reason.';
  }

  @override
  String get detNoEpisodes => 'Aucun épisode disponible pour cette série.';

  @override
  String detSeasonNumber(String number) {
    return 'Saison $number';
  }

  @override
  String detEpisodesShort(int count) {
    return '$count ép.';
  }

  @override
  String detRealOversold(String definition) {
    return '⚠ réel $definition';
  }

  @override
  String detReal(String definition) {
    return 'réel $definition';
  }

  @override
  String detResumeAt(String position) {
    return 'REPRENDRE · $position';
  }

  @override
  String detFavoriteAdded(String title) {
    return '⭐ « $title » ajouté aux favoris';
  }

  @override
  String detFavoriteRemoved(String title) {
    return '🗑️ « $title » retiré des favoris';
  }

  @override
  String get detNotInPlaylists =>
      'Pas dans vos listes — fiche affichée depuis TMDB.';

  @override
  String get detSearchInPlaylists => 'CHERCHER DANS MES LISTES';

  @override
  String get detStatusReleased => 'Sorti';

  @override
  String get detStatusPostProduction => 'Post-production';

  @override
  String get detStatusInProduction => 'En production';

  @override
  String get detStatusPlanned => 'Annoncé';

  @override
  String get detStatusReturning => 'En cours';

  @override
  String get detStatusEnded => 'Terminée';

  @override
  String get detStatusCanceled => 'Annulée';

  @override
  String get sheetDetails => 'Fiche Détaillée & Infos';

  @override
  String get sheetReplayUnavailable => 'Replay indisponible pour ce flux';

  @override
  String get onbSkip => 'Passer';

  @override
  String get onbNext => 'Suivant';

  @override
  String get onbStart => 'Commencer';

  @override
  String termPreviousErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ERREURS PRÉCÉDENTES',
      one: '$count ERREUR PRÉCÉDENTE',
    );
    return '$_temp0';
  }

  @override
  String get replayPickTitle => 'Choisir un moment à revoir';

  @override
  String get replayQuality => 'Qualité';

  @override
  String get replayDay => 'Jour';

  @override
  String get replayOrManually => 'OU CHOISIR MANUELLEMENT';

  @override
  String get replayStartTime => 'Heure de début';

  @override
  String get replayDuration => 'Durée';

  @override
  String replayAtWithDuration(String day, String time, String duration) {
    return '$day à $time ($duration)';
  }

  @override
  String get replayNoEpg => 'Aucune donnée EPG disponible';

  @override
  String get replayNoneTitle => 'Aucun replay disponible';

  @override
  String get replayNoneBody =>
      'Cette chaîne n\'expose pas d\'EPG Xtream ou son timeshift est désactivé. Essaie le picker manuel depuis l\'action sheet TV.';

  @override
  String expExpiredSince(int days, String date) {
    return 'Expirée depuis $days jours ($date)';
  }

  @override
  String expExpiresIn(int days, String date) {
    return 'Expire dans $days jours ($date)';
  }

  @override
  String get expTitleExpired => 'Playlist expirée';

  @override
  String get expTitleSoon => 'Playlist bientôt expirée';

  @override
  String get expBodyExpired =>
      'Cette playlist n\'est plus utilisable. Renouvelle auprès de ton provider pour reprendre l\'accès.';

  @override
  String get expBodySoon =>
      'Renouvelle auprès de ton provider pour ne pas perdre l\'accès.';

  @override
  String get expLater => 'Plus tard';

  @override
  String get expSeeDetails => 'Voir détails';

  @override
  String get memTitle => 'MÉMOIRE & STOCKAGE';

  @override
  String get memRefresh => 'Rafraîchir';

  @override
  String memEntriesAndSize(String count, String size) {
    return '$count entrées · $size';
  }

  @override
  String memOnDisk(String count, String size) {
    return 'sur disque · $count entrées · $size';
  }

  @override
  String memNoEntry(String size) {
    return '0 entrée · $size';
  }

  @override
  String get searchSheetTitle => 'Chercher dans mes listes';

  @override
  String get searchSheetFieldLabel => 'Titre à chercher';

  @override
  String searchSheetOriginalTitle(String title) {
    return 'Titre original : $title';
  }

  @override
  String get searchSheetTooShort => 'Saisis au moins 2 caractères.';

  @override
  String get searchSheetNoResult => 'Aucun titre trouvé dans vos listes.';

  @override
  String nextEpPlayNow(int seconds) {
    return 'Lire maintenant  ·  ${seconds}s';
  }

  @override
  String get aboutDiagnosticLog => 'Journal de diagnostic';

  @override
  String get aboutSourceOnGithub => 'Voir le code sur GitHub';

  @override
  String get aboutAllReleases => 'Toutes les releases';

  @override
  String get regionNoChange => 'Aucun changement';

  @override
  String get regionShowAll => 'Tout afficher';

  @override
  String get regionHideAll => 'Tout masquer';

  @override
  String get visualLangTitle => 'Langue des visuels';

  @override
  String get visualLangAuto => 'Comme le téléphone';

  @override
  String get visualLangOriginalLabel => 'Version originale (sans texte)';

  @override
  String get visualLangSubFr =>
      'Affiches et textes français quand ils existent';

  @override
  String get visualLangSubEn => 'Affiches et textes anglais';

  @override
  String get visualLangSubOriginal =>
      'Affiche sans texte quand elle existe, sinon la version d\'origine';

  @override
  String visualLangCurrently(String tag) {
    return 'Actuellement : $tag';
  }

  @override
  String get qualityHideVersions => 'Masquer les versions';

  @override
  String get qualityChangeVersion => 'Changer de version';

  @override
  String get navExitHint =>
      '💡 Pour quitter l\'application : appuie 2 fois sur Retour';

  @override
  String get navExitConfirm => 'Appuie à nouveau sur Retour pour quitter';

  @override
  String get settingsUsageReset => '🧹 Données d\'usage réinitialisées';

  @override
  String get errUnexpected => 'Une erreur inattendue est survenue.';

  @override
  String get errUnknown => 'Une erreur inconnue est survenue.';

  @override
  String get relayNothingReadable =>
      'La conversion n\'a rien produit de lisible.';

  @override
  String get reloadLessThanMinute => 'moins d\'une minute';

  @override
  String get bkFileTooShort => 'Fichier de sauvegarde trop court ou corrompu.';

  @override
  String get bkNotAnAetherFile => 'Ce n\'est pas un fichier .aether valide.';

  @override
  String get acctDefaultLabel => 'Compte par défaut';

  @override
  String get commonUnknown => 'Inconnu';

  @override
  String get dlMediaStoreTimeout => 'MediaStore n\'a pas répondu';

  @override
  String detRuntimePerEpisode(String minutes) {
    return '${minutes}m/épisode';
  }

  @override
  String get detEpisodesBadSeriesId => 'identifiant de série illisible';

  @override
  String get detEpisodesNoAccount => 'compte introuvable';

  @override
  String memSourceAndParsed(String source, String parsed) {
    return 'source $source · analysé $parsed';
  }

  @override
  String expTodayOn(String date) {
    return 'Expire aujourd\'hui ($date)';
  }

  @override
  String expTomorrowOn(String date) {
    return 'Expire demain ($date)';
  }

  @override
  String get catFavorites => 'Favoris';

  @override
  String get catOthers => 'Autres';

  @override
  String get catNew => 'New';

  @override
  String get catStaffPick => 'Coup de cœur';

  @override
  String get catSelection => 'Sélection';

  @override
  String get catCult => 'Cultes';

  @override
  String get catBoxOffice => 'Box Office';

  @override
  String get catOscar => 'Oscar';

  @override
  String get catAction => 'Action';

  @override
  String get catNews => 'Actualités';

  @override
  String get catAnimation => 'Animation';

  @override
  String get catMartialArts => 'Arts martiaux';

  @override
  String get catAdventure => 'Aventure';

  @override
  String get catBiopic => 'Biopic';

  @override
  String get catHeist => 'Braquage';

  @override
  String get catDisaster => 'Catastrophe';

  @override
  String get catComedy => 'Comédie';

  @override
  String get catCrime => 'Crime';

  @override
  String get catDance => 'Danse';

  @override
  String get catDocumentary => 'Documentaire';

  @override
  String get catDrama => 'Drame';

  @override
  String get catSpy => 'Espionnage';

  @override
  String get catFantasy => 'Fantastique';

  @override
  String get catHolidays => 'Fêtes';

  @override
  String get catWar => 'Guerre';

  @override
  String get catHistory => 'Histoire';

  @override
  String get catHorror => 'Horreur';

  @override
  String get catKids => 'Jeunesse';

  @override
  String get catLegal => 'Juridique';

  @override
  String get catKaraoke => 'Karaoké';

  @override
  String get catMafia => 'Mafia';

  @override
  String get catManga => 'Manga';

  @override
  String get catMaritime => 'Maritime';

  @override
  String get catMedical => 'Médecine';

  @override
  String get catMedieval => 'Médiéval';

  @override
  String get catMusical => 'Musical';

  @override
  String get catPolice => 'Policier';

  @override
  String get catPrison => 'Prison';

  @override
  String get catRomance => 'Romance';

  @override
  String get catSciFi => 'Sci-Fi';

  @override
  String get catStandUp => 'Spectacle';

  @override
  String get catSport => 'Sport';

  @override
  String get catSuperheroes => 'Super-Héros';

  @override
  String get catSurvival => 'Survie';

  @override
  String get catTvMovie => 'Téléfilm';

  @override
  String get catRealityTv => 'Téléréalité';

  @override
  String get catTalkShow => 'Talk-show';

  @override
  String get catThriller => 'Thriller';

  @override
  String get catSerialKiller => 'Tueur en série';

  @override
  String get catRevenge => 'Vengeance';

  @override
  String get catCars => 'Voitures';

  @override
  String get catWestern => 'Western';

  @override
  String get regFrance => 'France';

  @override
  String get regAlbania => 'Albanie';

  @override
  String get regAlgeria => 'Algérie';

  @override
  String get regGermany => 'Allemagne';

  @override
  String get regArmenia => 'Arménie';

  @override
  String get regAsia => 'Asie';

  @override
  String get regBelgium => 'Belgique';

  @override
  String get regBosnia => 'Bosnie';

  @override
  String get regBrazil => 'Brésil';

  @override
  String get regCanada => 'Canada';

  @override
  String get regCroatia => 'Croatie';

  @override
  String get regSpain => 'Espagne';

  @override
  String get regGreece => 'Grèce';

  @override
  String get regIndian => 'Indien';

  @override
  String get regItaly => 'Italie';

  @override
  String get regMaghreb => 'Maghrébin';

  @override
  String get regNetherlands => 'Pays-Bas';

  @override
  String get regPoland => 'Pologne';

  @override
  String get regPortugal => 'Portugal';

  @override
  String get regRamadan => 'Ramadan';

  @override
  String get regRomania => 'Roumanie';

  @override
  String get regRussia => 'Russie';

  @override
  String get regScandinavia => 'Scandinavie';

  @override
  String get regSwitzerland => 'Suisse';

  @override
  String get regCzechia => 'Tchéquie';

  @override
  String get regExYugoslavia => 'Ex-Yougoslavie';

  @override
  String get regDominicanRepublic => 'Rép. Dominicaine';

  @override
  String get regOriginalNonFrench => 'VO (non-FR)';

  @override
  String get regLegendado => 'Brésil — VO sous-titrée';

  @override
  String get regBrazilGroup => 'Brésil (doublé, VO sous-titrée, nouveautés)';

  @override
  String get regEnglishGroup => 'Anglais (Royaume-Uni, États-Unis)';

  @override
  String get regExYugoslaviaGroup => 'Ex-Yougoslavie (Bosnie, Croatie)';

  @override
  String get acctChipMain => 'PRINCIPAL';

  @override
  String get bootEnterManually => 'Saisir manuellement';

  @override
  String get bootConfigureWebConsole => 'Configurer via Console web';

  @override
  String get searchPeople => 'Personnes';

  @override
  String get personRoleDirector => 'Réalisateur';

  @override
  String get personRoleActor => 'Acteur';

  @override
  String get personRoleWriter => 'Scénariste';

  @override
  String get personRoleProduction => 'Production';

  @override
  String get personRoleMusic => 'Musique';

  @override
  String get personRoleCamera => 'Image';

  @override
  String get tracksAudio => 'Audio';

  @override
  String get tracksSubtitles => 'Sous-titres';

  @override
  String get epgNow => 'EN COURS';

  @override
  String get epgNext => 'ENSUITE';

  @override
  String get replayPrograms => 'Programmes';

  @override
  String get replayToday => 'Aujourd’hui';

  @override
  String get replayYesterday => 'Hier';

  @override
  String replayWatchLabel(String label) {
    return 'Regarder  •  $label';
  }

  @override
  String qualityWatch(String label) {
    return 'Regarder · $label';
  }

  @override
  String get actorBiography => 'Biographie';

  @override
  String get actorBiographyMissing => 'Biographie indisponible.';

  @override
  String get actorAvailableBadge => 'DISPO';

  @override
  String get detMainCast => 'Casting principal';

  @override
  String get detSimilarAvailable => 'Titres similaires disponibles';

  @override
  String get detTrailerButton => 'BANDE-ANNONCE';

  @override
  String get themePreviewTitle => 'Titre du Film';

  @override
  String get sheetReplay => 'Replay';

  @override
  String sheetReplayDays(int days) {
    return 'Replay (${days}j)';
  }

  @override
  String get memComputing => 'Calcul en cours…';

  @override
  String get memRamProcess => 'RAM process';

  @override
  String memRamProcessValue(String current, String peak) {
    return '$current (pic $peak)';
  }

  @override
  String get memImageCacheDisk => 'Cache images (disque)';

  @override
  String get memImageCacheRam => 'Cache images (RAM)';

  @override
  String memImageCacheRamValue(
    String used,
    String max,
    String count,
    String maxCount,
  ) {
    return '$used / $max · $count / $maxCount img';
  }

  @override
  String sizeBytes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n octets',
      one: '$n octet',
    );
    return '$_temp0';
  }

  @override
  String sizeKilobytes(String n) {
    return '$n Ko';
  }

  @override
  String sizeMegabytes(String n) {
    return '$n Mo';
  }

  @override
  String sizeGigabytes(String n) {
    return '$n Go';
  }

  @override
  String get dlActionRestart => 'Relancer';

  @override
  String get dlMoreActions => 'Autres actions';

  @override
  String get playerQuit => 'Quitter';

  @override
  String get nextEpContinue => 'Continuer';

  @override
  String get commonClear => 'Effacer';

  @override
  String get statsAnnouncedLabel => 'Annoncé';

  @override
  String get replayGuideUnavailable => 'Guide indisponible';

  @override
  String get replayNotAvailable => 'non disponible';

  @override
  String get detEnableTmdb => 'Active TMDB';

  @override
  String get dlRestartUpper => 'RELANCER';

  @override
  String get commonDecrease => 'Diminuer';

  @override
  String get commonIncrease => 'Augmenter';

  @override
  String get detEpisodesReasonNetwork => 'le serveur ne répond pas';

  @override
  String get detEpisodesReasonBusy =>
      'le fournisseur refuse : trop de connexions en même temps';

  @override
  String get detEpisodesReasonParse => 'la réponse du serveur est illisible';

  @override
  String get detEpisodesReasonAccount =>
      'les réglages du compte sont incomplets';

  @override
  String failDetailTooLong(String delay) {
    return '(toujours pas prête après $delay)';
  }

  @override
  String get failDetailCacheCleared => '(vidé à ta demande)';

  @override
  String durationHoursMinutes(int hours, String minutes) {
    return '${hours}h$minutes';
  }

  @override
  String durationMinutes(int count) {
    return '$count min';
  }

  @override
  String durationSeconds(int count) {
    return '$count s';
  }

  @override
  String get healthNoStalls => 'aucun blocage';

  @override
  String healthStalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocages',
      one: '$count blocage',
    );
    return '$_temp0';
  }

  @override
  String healthPerHour(String value) {
    return '$value/h';
  }

  @override
  String healthWatched(String duration) {
    return '$duration vues';
  }

  @override
  String bootDetailEntries(int n, String count) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$count entrées',
      one: '$count entrée',
    );
    return '$_temp0';
  }

  @override
  String bootDetailSection(String section, String done, String total) {
    return '$section · $done/$total';
  }

  @override
  String get bootSectionLive => 'chaînes';

  @override
  String get bootSectionMovies => 'films';

  @override
  String get bootSectionSeries => 'séries';

  @override
  String get bootStepInit => '// initialisation…';

  @override
  String get bootStepServices => '// préparation des services…';

  @override
  String get bootStepAccount => '// vérification du compte…';

  @override
  String get bootStepReadPlaylist => '// lecture de la playlist…';

  @override
  String get bootStepDownloadPlaylist => '// téléchargement de la playlist…';

  @override
  String get bootStepAnalysis => '// analyse du catalogue…';

  @override
  String get bootStepOtherAccounts => '// chargement des autres comptes…';

  @override
  String get bootStepReady => '// prêt.';

  @override
  String bootStepUpdate(int index, int total, String label) {
    return '// mise à jour $index/$total · $label…';
  }

  @override
  String bootStepAnalysisOf(String label) {
    return '// analyse · $label…';
  }

  @override
  String get playlistNoActiveAccount =>
      'Aucun compte actif sélectionné. Choisis-en un dans les paramètres.';

  @override
  String playlistInvalidUrl(String label) {
    return 'L’URL de la playlist du compte « $label » est invalide. Vérifie sa configuration.';
  }

  @override
  String detRuntimeHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get castOverlayLive => 'EN DIRECT';

  @override
  String playerReconnectingNow(int attempt, int max) {
    return 'Reconnexion… ($attempt/$max)';
  }

  @override
  String get nextEpStayHere => 'Rester ici';

  @override
  String get nowPlayingLive => 'En direct';

  @override
  String get nowPlayingReplay => 'Replay';

  @override
  String tracksTrackN(String id) {
    return 'Piste $id';
  }

  @override
  String replayManualTitle(String label) {
    return 'Replay — $label';
  }

  @override
  String get relayDolbyVisionP5 =>
      'Ce film est en Dolby Vision profil 5 : sans décodeur Dolby Vision, l\'image aurait des couleurs fausses. Il ne peut pas être converti pour le téléviseur.';

  @override
  String get dlNotifFinished => 'Téléchargement terminé — appuyer pour ouvrir';

  @override
  String get dlNotifFailed => 'Échec du téléchargement';

  @override
  String get castNotifStop => 'Arrêter';

  @override
  String dlNoticeAverage(int percent) {
    return '$percent % en moyenne';
  }

  @override
  String get termShow => '▼ AFFICHER';

  @override
  String get termHide => '▲ MASQUER';

  @override
  String get updDiffLine => '> DIFF    : voir la release sur GitHub';

  @override
  String get updViewChangelog => '[ VOIR LES NOUVEAUTÉS ]';

  @override
  String get updLater => '[ PLUS TARD ]';

  @override
  String get updAbort => '[ ANNULER ]';

  @override
  String get updInstall => '[ INSTALLER ]';

  @override
  String get updRetry => '[ RÉESSAYER ]';

  @override
  String get xmltvNoGuide => 'Aucun guide enregistré';

  @override
  String get consoleCodeLabel => 'Code : ';

  @override
  String get consoleCopyUrl => 'Copier l\'adresse';

  @override
  String bkBackupFrom(String date, String version) {
    return 'Sauvegarde du $date (v$version) :';
  }

  @override
  String qualityStreamN(int n) {
    return 'Flux $n';
  }

  @override
  String searchVersionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versions',
      one: '$count version',
    );
    return '$_temp0';
  }

  @override
  String get aboutVersionLabel => 'VERSION';

  @override
  String aboutMadeWith(String stack) {
    return 'Fait avec $stack';
  }

  @override
  String get acctCardActions => 'Actions du compte';

  @override
  String infoRowLabel(String label) {
    return '$label :';
  }

  @override
  String get detSynopsis => 'Synopsis';

  @override
  String detVotes(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted votes',
      one: '$formatted vote',
    );
    return '$_temp0';
  }

  @override
  String get actorJobDirecting => 'Équipe de réalisation';

  @override
  String get themePresetPhosphore => 'Phosphore';

  @override
  String get themePresetNordique => 'Nordique';

  @override
  String get themePresetMinimaliste => 'Minimaliste';

  @override
  String dlNoticeSizeOf(String received, String total) {
    return '$received sur $total';
  }

  @override
  String get dlNotifChannelDone => 'Téléchargements terminés';

  @override
  String get dlActionCast => 'Diffuser';

  @override
  String perfParallelDownloadsPerHostSub(int count) {
    return 'Un transfert à la fois par abonnement ; jusqu\'à $count abonnements peuvent travailler ensemble.';
  }

  @override
  String get playOffline => 'Lire hors ligne';

  @override
  String get dlBadgeDownloaded => 'Téléchargé';

  @override
  String get dlErrFileMissing => 'Ce fichier n\'est plus sur l\'appareil.';

  @override
  String get playBusyTitle => 'Cet abonnement est occupé';

  @override
  String get playBusyElsewhere =>
      'Un autre écran regarde déjà sur cet abonnement. La lecture risque d\'être refusée.';

  @override
  String get playBusyOwnTransfer =>
      'Vos téléchargements occupent toutes les connexions de cet abonnement. En mettre un en pause libère la lecture.';

  @override
  String get playBusyContinue => 'Lire quand même';

  @override
  String bkPartSavedThemes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thèmes enregistrés',
      one: '1 thème enregistré',
    );
    return '$_temp0';
  }

  @override
  String get themeSectionMyThemes => 'Mes thèmes';

  @override
  String get themeMyThemesEmpty =>
      'Aucun thème enregistré. Réglez vos couleurs, puis « Enregistrer sous… ».';

  @override
  String get themeSaveAs => 'Enregistrer sous…';

  @override
  String get themeSaveAsTitle => 'Enregistrer ce thème';

  @override
  String get themeNameHint => 'Nom du thème';

  @override
  String themeSavedDone(String name) {
    return 'Thème « $name » enregistré';
  }

  @override
  String themeSaveFull(int count) {
    return 'Vous pouvez garder $count thèmes au maximum. Supprimez-en un pour en enregistrer un autre.';
  }

  @override
  String get themeNameTaken => 'Un thème porte déjà ce nom.';

  @override
  String themeAppliedDone(String name) {
    return 'Thème « $name » appliqué';
  }

  @override
  String get themeRename => 'Renommer';

  @override
  String get themeRenameTitle => 'Renommer ce thème';

  @override
  String themeDeleteTitle(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String get themeDeleteQuestion =>
      'Il disparaît de la liste. Les couleurs affichées ne changent pas.';

  @override
  String get themeDeleteDone => 'Thème supprimé';

  @override
  String get themeKeepBeforeResetTitle => 'Garder ces couleurs ?';

  @override
  String get themeKeepBeforeResetBody =>
      'Elles ne correspondent à aucun préréglage ni thème enregistré : réinitialiser les perd.';

  @override
  String get themeKeepBeforeResetSave => 'Enregistrer d\'abord';

  @override
  String get themeKeepBeforeResetSkip => 'Réinitialiser quand même';

  @override
  String get themeColorFree => 'Autre couleur';

  @override
  String get themeColorFreeTitle => 'Choisir une couleur';

  @override
  String get themeHex => 'Code hexadécimal';

  @override
  String get themeHexInvalid =>
      'Six caractères après le #, par exemple #00FF41';

  @override
  String get themeHue => 'Teinte';

  @override
  String get themeSaturation => 'Saturation';

  @override
  String get themeLightness => 'Luminosité';

  @override
  String get themePreviewFavorite => 'Favori';

  @override
  String get themePreviewAlert => 'Reprendre';

  @override
  String get themePreviewError => 'Flux indisponible';

  @override
  String get themePreviewSuccess => 'Téléchargé';

  @override
  String themeEditColor(String label) {
    return 'Changer $label';
  }

  @override
  String get themeSavedApply => 'Appliquer';

  @override
  String get acctReadingPlaylist => 'Lecture de la liste…';

  @override
  String get optQualityTitle => 'Qualité';

  @override
  String get optQualityAuto => 'Automatique';

  @override
  String get optQualityAutoSub => 'Suit votre connexion';

  @override
  String get optQualityFailed => 'Cette qualité n\'a pas pu être appliquée';

  @override
  String get detMoreBelow => 'Suite de la fiche plus bas';

  @override
  String get detSeeMoreCast => 'Voir plus';

  @override
  String get settingsSubtitles => 'Sous-titres en ligne';

  @override
  String get settingsSubtitlesSub =>
      'Trouver des sous-titres pour un film qui n’en a pas';

  @override
  String get subProviderTitle => 'Sous-titres en ligne';

  @override
  String get subProviderActive => 'Prêt';

  @override
  String get subProviderActiveSub =>
      'Vous pouvez maintenant chercher des sous-titres pendant un film';

  @override
  String get subProviderInactive => 'Aucune clé enregistrée';

  @override
  String get subProviderInactiveSub =>
      'Une clé permet à l’application de chercher des sous-titres pour vous';

  @override
  String get subProviderIntro =>
      'Certains films et épisodes arrivent sans sous-titres. L’application peut aller en chercher, mais le service de sous-titres a besoin de savoir qui les demande. Obtenir votre accès est gratuit et prend une minute.';

  @override
  String get subProviderStep1 =>
      'Ouvrez le service de sous-titres et confirmez votre adresse e-mail.';

  @override
  String get subProviderStep2 => 'Copiez la clé qu’il vous donne.';

  @override
  String get subProviderStep3 => 'Collez-la ci-dessous, puis enregistrez.';

  @override
  String get subProviderGetKey => 'Obtenir une clé gratuite';

  @override
  String get subProviderSection => 'VOTRE CLÉ';

  @override
  String get subProviderHint => 'Collez votre clé ici';

  @override
  String get subProviderShow => 'Afficher';

  @override
  String get subProviderHide => 'Masquer';

  @override
  String get subProviderSave => 'Enregistrer';

  @override
  String get subProviderRemove => 'Retirer cette clé';

  @override
  String get subProviderSaved => 'Clé enregistrée';

  @override
  String get subProviderRemoved => 'Clé retirée';

  @override
  String get tracksSearchOnline => 'Chercher des sous-titres en ligne';

  @override
  String get tracksSearchOnlineSub => 'Pour ce film ou cet épisode';

  @override
  String get tracksOnlineSearching => 'Recherche…';

  @override
  String get tracksOnlineHearing => 'Pour sourds et malentendants';

  @override
  String get tracksOnlineAdded => 'Sous-titres ajoutés';

  @override
  String get tracksOnlineAddFailed =>
      'Ces sous-titres n’ont pas pu être ajoutés';

  @override
  String get tracksOnlineNone => 'Aucun sous-titre trouvé pour celui-ci';

  @override
  String get tracksOnlineNoTitle => 'Ce titre n’a pas pu être reconnu';

  @override
  String get tracksOnlineNoKey =>
      'Configurez d’abord les sous-titres en ligne dans les Réglages';

  @override
  String get tracksOnlineBadKey =>
      'Votre clé a été refusée — vérifiez-la dans les Réglages';

  @override
  String get tracksOnlineQuota => 'Vous avez utilisé vos recherches du jour';

  @override
  String get tracksOnlineFailed => 'La recherche n’a pas pu aboutir';

  @override
  String themeDefaultName(int n) {
    return 'Mon thème $n';
  }

  @override
  String tvOptSpeedValue(String speed) {
    return '$speed×';
  }

  @override
  String get tvOptSubsOff => 'Coupés';

  @override
  String get tvOptAuto => 'Automatique';

  @override
  String get tvOptStatsShown => 'Affichées';

  @override
  String get tvOptStatsHidden => 'Masquées';
}
