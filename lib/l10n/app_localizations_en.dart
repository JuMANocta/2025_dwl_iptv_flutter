// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get downloadManagerTitle => 'Download Manager';

  @override
  String get noDownloads => 'No downloads';

  @override
  String get downloadDialogTitle => 'Start Download';

  @override
  String get downloadDialogFileNameLabel => 'File name';

  @override
  String get downloadDialogFileSizeLabel => 'File size';

  @override
  String get downloadDialogFileTypeLabel => 'File type';

  @override
  String get downloadDialogUnknownSize => 'Unknown';

  @override
  String get cancel => 'Cancel';

  @override
  String get download => 'Download';

  @override
  String get denied => 'Permission denied. The download cannot begin.';

  @override
  String get terminalTitle => '//:FLUX_DOWNLOAD_INTERFACE';

  @override
  String terminalResumeMessage(Object fileName) {
    return '🔄 Resuming download:\n🎞️ $fileName';
  }

  @override
  String terminalStartMessage(Object fileName) {
    return '🤖 Starting download:\n🎞️ $fileName';
  }

  @override
  String terminalFileSizeMessage(Object fileSize) {
    return '📦 File size: $fileSize';
  }

  @override
  String get terminalFinalizingMessage =>
      '\n⚙️ Finalizing...\nMoving file to public storage. Please wait.';

  @override
  String get terminalSuccessMessage => '\n🟢 SUCCESS: Download complete!';

  @override
  String get terminalFatalErrorMessage => '\n☣️ FATAL: An error occurred';

  @override
  String get terminalSpeedMessage => 'Speed';

  @override
  String get terminalRetryCountMessage => 'Retries';

  @override
  String get terminalEtaMessage => 'ETA';

  @override
  String get terminalCancelMessage => '\nℹ️ ABORT: Download cancelled by user';

  @override
  String get terminalCloseButton => '[ CLOSE ]';

  @override
  String get terminalAbortingButton => '[ PAUSE... ]';

  @override
  String get terminalAbortButton => '[ PAUSE ]';

  @override
  String get searchPageDownloadsTooltip => 'See downloads';

  @override
  String get searchPageReloadTooltip => 'Reload playlist';

  @override
  String get searchPageAccountsTooltip => 'Accounts and Settings';

  @override
  String get searchPageLoadingError => 'Could not load playlist';

  @override
  String get searchPageRetryButton => 'Retry';

  @override
  String get searchPageProcessingError => 'Error processing playlist:';

  @override
  String get searchFieldHint => 'Search...';

  @override
  String get searchFilterFilms => 'Movies';

  @override
  String get searchFilterSeries => 'Series';

  @override
  String get searchFilterTv => 'TV';

  @override
  String get searchNoResults => 'No results found.';

  @override
  String get searchNoContent => 'No content to display.';

  @override
  String get actionSheetChooseVersion => 'Choose a version for:';

  @override
  String chipSeasons(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seasons',
      one: '1 Season',
    );
    return '$_temp0';
  }

  @override
  String chipEpisodes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ep.',
      one: '1 Ep.',
    );
    return '$_temp0';
  }

  @override
  String get season => 'Season';

  @override
  String get episode => 'Episode';

  @override
  String get favoriteAdd => 'Add to favorites';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String get actionSheetPlay => 'Play';

  @override
  String get actionSheetPlaySubtitle => 'Starts playback (automatic caching).';

  @override
  String get actionSheetDownload => 'Download in background';

  @override
  String get actionSheetDownloadSubtitle =>
      'To watch later without a connection.';

  @override
  String get deleteDialogTitle => 'Delete file?';

  @override
  String get deleteDialogSizeLabel => 'Size';

  @override
  String get deleteDialogWarning =>
      'This action is irreversible and the file will be permanently deleted.';

  @override
  String get deleteDialogConfirmButton => 'Delete';

  @override
  String get deleteTooltip => 'Delete permanently';

  @override
  String get taskStatusDownloading => 'Downloading...';

  @override
  String taskStatusRemaining(Object remainingSize) {
    return ' • $remainingSize left';
  }

  @override
  String taskStatusCompleted(Object date, Object size) {
    return 'Completed • $size • $date';
  }

  @override
  String taskStatusFailed(Object progressInfo) {
    return 'Failed $progressInfo • Tap to retry';
  }

  @override
  String taskStatusCanceled(Object progressInfo) {
    return 'Canceled $progressInfo • Tap to retry';
  }

  @override
  String taskStatusPending(Object date) {
    return 'Pending • $date';
  }

  @override
  String get taskStatusUnknownError => 'Unknown error';

  @override
  String get playlistCardSubtitleNone =>
      'No playlist downloaded in this context.';

  @override
  String playlistCardSubtitleLastFile(Object path) {
    return 'Last file: $path';
  }

  @override
  String get playlistDownloadButton => 'Download / Update';

  @override
  String get playlistDeleteButton => 'Delete';

  @override
  String get playlistManagementTip =>
      'Tip: You can also reload the playlist from the settings gear or via the refresh icon on the search screen.';

  @override
  String get accountsTitle => 'Account Management';

  @override
  String get deleteAccountDialogTitle => 'Delete account?';

  @override
  String get deleteAccountDialogContent => 'This action is permanent.';

  @override
  String get deleteAccountConfirm => 'Delete';

  @override
  String get playlistInfoChecking => 'Checking playlist...';

  @override
  String get playlistInfoUnavailable =>
      'No playlist available or loading error.';

  @override
  String get playlistInfoTryReload => 'Try reloading';

  @override
  String get playlistInfoLocalFile => 'Local playlist file';

  @override
  String get playlistInfoSize => 'Size';

  @override
  String get playlistInfoLastUpdate => 'Upd.';

  @override
  String get playlistInfoEntries => 'Entries';

  @override
  String get playlistInfoReloadButton => 'Reload';

  @override
  String get playlistInfoDeleteButton => 'Delete';

  @override
  String get accountsListEmpty => 'Add an account';

  @override
  String accountModeComplete(Object host) {
    return 'Mode: Full URL — $host';
  }

  @override
  String accountModeSeparate(Object host, Object username) {
    return 'Mode: Separate — $username@$host';
  }

  @override
  String get accountActionEdit => 'Edit';

  @override
  String get accountActionDelete => 'Delete';

  @override
  String get accountsFab => 'New';

  @override
  String get editAccountTitleAdd => 'Add Account';

  @override
  String get editAccountTitleEdit => 'Edit Account';

  @override
  String get editAccountNameLabel =>
      'Account name (e.g., Living Room, Vacation...)';

  @override
  String get editAccountNameHint => 'My IPTV Account';

  @override
  String get editAccountNameRequired => 'Required';

  @override
  String get editAccountModeUrl => 'Full URL';

  @override
  String get editAccountModeCredentials => 'Credentials';

  @override
  String get editAccountFullUrlLabel => 'Full .m3u URL';

  @override
  String get editAccountFullUrlInvalid => 'Invalid URL';

  @override
  String get editAccountServerUrlLabel => 'Server URL (e.g., http://host:port)';

  @override
  String get editAccountUsernameLabel => 'Username';

  @override
  String get editAccountPasswordLabel => 'Password';

  @override
  String get editAccountPlaylistTypeLabel => 'Playlist type';

  @override
  String get editAccountPlaylistTypeM3u => 'M3U (Standard)';

  @override
  String get editAccountPlaylistTypeSimple => 'Simple (Single link)';

  @override
  String get editAccountCookiesLabel => 'Cookies (optional)';

  @override
  String get editAccountCookiesHint => 'e.g., PHPSESSID=xxxxxx;';

  @override
  String get editAccountSaveButton => 'Save';

  @override
  String get playerGenericError => 'Unable to play this media.';

  @override
  String get playerLoading => 'Initializing player...';

  @override
  String playerLoadingError(Object error) {
    return 'Loading error: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get aboutTitle => 'About';

  @override
  String get backupTitle => 'Backup';

  @override
  String get optimizationTitle => 'Optimization';

  @override
  String get regionFilterTitle => 'Languages / regions';

  @override
  String get themeSettingsTitle => 'Appearance';

  @override
  String get tmdbKeyTitle => 'TMDB API key';

  @override
  String get xmltvTitle => 'Channel guide';

  @override
  String get webConsoleTitle => 'Web console';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsSectionPhone => 'Control from your phone';

  @override
  String get settingsWebConsole => 'Web console';

  @override
  String get settingsWebConsoleSub =>
      'Accounts, backup, theme, EPG, TMDB + remote (QR)';

  @override
  String get settingsSectionSources => 'Sources & accounts';

  @override
  String get settingsAccounts => 'IPTV accounts';

  @override
  String get settingsAccountsSub => 'Providers, playlist stats & reload';

  @override
  String get settingsTmdbKey => 'TMDB API key';

  @override
  String get settingsTmdbKeySub => 'Posters, overviews, cast (optional)';

  @override
  String get settingsXmltv => 'Channel guide';

  @override
  String get settingsXmltvSub => 'XMLTV EPG — French DTT';

  @override
  String get settingsSectionDisplay => 'Display';

  @override
  String get settingsRegions => 'Languages / regions';

  @override
  String get settingsRegionsSub => 'Hide foreign content (saves memory)';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeSub => 'Theme, colours, cyberpunk effects';

  @override
  String get settingsOptimization => 'Performance';

  @override
  String get settingsOptimizationSub =>
      'Performance profiles, hero, thumbnails, memory';

  @override
  String get settingsSectionBackup => 'Backup & app';

  @override
  String get settingsBackup => 'Backup / Restore';

  @override
  String get settingsBackupSub =>
      'Export/import accounts, TMDB, theme, favourites (encrypted .aether)';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSub => 'Version + update check';

  @override
  String get settingsResetUsage => 'Reset usage data';

  @override
  String get settingsResetUsageSub =>
      'Clears favourites, resume points & history (keeps accounts & theme)';

  @override
  String get settingsResetTitle => 'Reset usage data?';

  @override
  String get settingsResetBody =>
      'Clears favourites, resume points (movies & series), search history and the last watched channel.\n\nKeeps IPTV accounts, the TMDB key, the theme and the language/region filters.\n\nThis cannot be undone.';

  @override
  String get settingsResetConfirm => 'Reset';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get errNetworkUnreachable =>
      'Cannot connect: no network, or the server is unreachable.';

  @override
  String get errTimeout => 'The server took too long to answer.';

  @override
  String get errTimeoutHint =>
      'The server took too long to answer. Check your connection or the server address.';

  @override
  String get errTls => 'Secure connection refused by the server (certificate).';

  @override
  String get errBadFormat =>
      'Unreadable answer from the server (unexpected format).';

  @override
  String get errFileSystem => 'Cannot read or write the file on this device.';

  @override
  String get errInternal => 'Something went wrong inside the app.';

  @override
  String get errBadResponse =>
      'Invalid answer from the server. Check the address.';

  @override
  String errForbidden(int code) {
    return 'Access denied by the server (HTTP $code). Check the account credentials.';
  }

  @override
  String get errNotFound => 'Address not found on the server (HTTP 404).';

  @override
  String errServer(int code) {
    return 'The server is failing (HTTP $code). Try again later.';
  }

  @override
  String errHttp(int code) {
    return 'The server answered with an error (HTTP $code).';
  }

  @override
  String get errConnection =>
      'Connection error: check that you are online and that the server is reachable.';

  @override
  String get errCancelled => 'Operation cancelled.';

  @override
  String get errNetworkUnknown => 'Unknown network error.';

  @override
  String rowBecauseYouWatched(String title) {
    return 'Because you watched “$title”';
  }

  @override
  String get rowTopRated => 'Top rated';

  @override
  String get tmdbRowsBecauseTitle => '“Because you watched” row';

  @override
  String get tmdbRowsBecauseSub =>
      'Titles close to what you last watched, picked from your lists';

  @override
  String get tmdbRowsTopRatedTitle => '“Top rated” row';

  @override
  String get tmdbRowsTopRatedSub => 'The best-rated titles your lists offer';

  @override
  String get perfMinItemsTitle => 'Rows: minimum titles';

  @override
  String get perfMinItemsSub =>
      'Below this, the row folds into “Others” — never New or Favourites. 1 = never fold.';

  @override
  String get dlOnDeviceTitle => 'On this device';

  @override
  String dlOnDeviceSub(int count, String size) {
    return '$count file(s) · $size — in Movies/AetherStream, missing from the list';
  }

  @override
  String get dlScanTooltip => 'Look for files on this device';

  @override
  String dlScanFound(int count, String size) {
    return '$count file(s) on device, missing from the list ($size)';
  }

  @override
  String get dlScanNothing => 'Nothing new on this device';

  @override
  String get dlScanDenied => 'Without video access, the folder cannot be read';

  @override
  String get dlOrphanDeleteTitle => 'Delete this file?';

  @override
  String dlOrphanDeleteBody(String name, String size) {
    return '“$name” ($size) will be erased from this device. This cannot be undone.';
  }

  @override
  String get dlOrphanDeleted => 'File deleted';

  @override
  String get dlOrphanDeleteFailed => 'Android refused the deletion';

  @override
  String get dlOrphanPlay => 'Play';

  @override
  String get commonDelete => 'Delete';

  @override
  String get tmdbStatusOn => 'TMDB connected: posters, overviews and cast';

  @override
  String get tmdbStatusOff =>
      'No TMDB key: no extra posters or overviews. The app still works.';

  @override
  String get tmdbPairReplace => 'Replace from my phone';

  @override
  String get tmdbPairSetup => 'Set up from my phone';

  @override
  String get tmdbPairSub =>
      'Scan the QR code and paste the key from your phone';

  @override
  String get tmdbKeySection => 'TMDB key';

  @override
  String get tmdbKeySectionManual => 'Typing with the remote';

  @override
  String get tmdbKeyHint => 'Paste your key here…';

  @override
  String get tmdbKeyShow => 'Show';

  @override
  String get tmdbKeyHide => 'Hide';

  @override
  String get tmdbKeySave => 'Save';

  @override
  String get tmdbKeyRemove => 'Remove the key';

  @override
  String get tmdbKeyManualEntry => 'Type it with the remote';

  @override
  String get tmdbKeyConnected => 'TMDB connected';

  @override
  String get tmdbKeyRemoved => 'TMDB key removed';

  @override
  String get tmdbKeyRejected =>
      'TMDB rejected this key. Make sure you copied the API Read Access Token.';

  @override
  String get tmdbKeyUnverified =>
      'Key saved. It could not be checked right now (no network).';

  @override
  String get tmdbKeyChecking => 'Checking…';

  @override
  String get tmdbHowTitle => 'Get a key (free)';

  @override
  String get tmdbHowStep1 => 'Create an account on themoviedb.org';

  @override
  String get tmdbHowStep2 => 'Open Settings, then API';

  @override
  String get tmdbHowStep3 => 'Copy the API Read Access Token';

  @override
  String get tmdbHowStep4 => 'Paste it below';

  @override
  String get tmdbSignup => 'Create a TMDB account';

  @override
  String get tmdbLogin => 'I already have an account';

  @override
  String get tmdbOptionsTitle => 'Options';

  @override
  String get tmdbVisualLangTitle => 'Language of visuals';

  @override
  String tmdbVisualLangSub(String lang) {
    return '$lang: posters, overviews and cast';
  }

  @override
  String get tmdbPostersFirstTitle => 'TMDB posters first';

  @override
  String get tmdbPostersFirstOn =>
      'In the carousel and favourites, the TMDB poster replaces the list\'s';

  @override
  String get tmdbPostersFirstOff =>
      'Posters come from your lists; TMDB fills in the missing ones';

  @override
  String get tmdbMemoryTitle => 'Stored data';

  @override
  String get tmdbMemoryPosters => 'Posters';

  @override
  String get tmdbMemoryPostersNone => 'No poster stored yet';

  @override
  String tmdbMemoryPostersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posters stored',
      one: '1 poster stored',
    );
    return '$_temp0';
  }

  @override
  String get tmdbMemoryClear => 'Clear';

  @override
  String get tmdbMemoryPostersCleared =>
      'Posters cleared. They will reload as you browse.';

  @override
  String get tmdbMemorySorting => 'Automatic sorting';

  @override
  String get tmdbMemorySortingNone =>
      'Nothing to relearn: your lists already sort their titles';

  @override
  String tmdbMemorySortingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles sorted thanks to TMDB',
      one: '1 title sorted thanks to TMDB',
    );
    return '$_temp0';
  }

  @override
  String get tmdbMemoryRelearn => 'Relearn';

  @override
  String get tmdbMemorySortingCleared =>
      'Sorting cleared. It will rebuild as you browse the home.';
}
