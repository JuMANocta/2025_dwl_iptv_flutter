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
  String get terminalEtaMessage => 'ETA';

  @override
  String get terminalElapsedMessage => 'Elapsed';

  @override
  String get terminalCancelMessage => '\nℹ️ ABORT: Download cancelled by user';

  @override
  String get terminalCloseButton => '[ CLOSE ]';

  @override
  String get terminalAbortingButton => '[ PAUSE... ]';

  @override
  String get terminalAbortButton => '[ PAUSE ]';

  @override
  String get episode => 'Episode';

  @override
  String get favoriteAdd => 'Add to favorites';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String get actionSheetPlay => 'Play';

  @override
  String get actionSheetDownload => 'Download in background';

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
  String get accountsTitle => 'Account Management';

  @override
  String get deleteAccountDialogTitle => 'Delete account?';

  @override
  String get deleteAccountConfirm => 'Delete';

  @override
  String get accountActionEdit => 'Edit';

  @override
  String get accountActionDelete => 'Delete';

  @override
  String get editAccountTitleAdd => 'Add Account';

  @override
  String get editAccountTitleEdit => 'Edit Account';

  @override
  String get editAccountNameLabel =>
      'Account name (e.g., Living Room, Vacation...)';

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
  String get editAccountSaveButton => 'Save';

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
  String get tmdbKeyTitle => 'TMDB posters & info';

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
  String get settingsTmdbKey => 'TMDB posters & info';

  @override
  String get settingsTmdbKeySub => 'Posters, overviews, cast — optional';

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
  String get settingsThemeSub => 'Theme, colors, cyberpunk effects';

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
      'Export/import accounts, TMDB, theme, favorites (encrypted .aether)';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSub => 'Version + update check';

  @override
  String get settingsResetUsage => 'Reset usage data';

  @override
  String get settingsResetUsageSub =>
      'Clears favorites, resume points & history (keeps accounts & theme)';

  @override
  String get settingsResetTitle => 'Reset usage data?';

  @override
  String get settingsResetBody =>
      'Clears favorites, resume points (movies & series), search history and the last watched channel.\n\nKeeps IPTV accounts, the TMDB key, the theme and the language/region filters.\n\nThis cannot be undone.';

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
      'Below this, the row folds into “Others” — never New or Favorites. 1 = never fold.';

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
  String get tmdbKeyRemoveTitle => 'Remove the TMDB key?';

  @override
  String get tmdbKeyRemoveQuestion =>
      'Posters and info from TMDB will no longer load until a key is entered again.';

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
      'Carousel and favorites use the TMDB poster.';

  @override
  String get tmdbPostersFirstOff =>
      'Carousel and favorites keep your lists\' poster.';

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

  @override
  String get reloadAllTitle => 'Reload all lists?';

  @override
  String reloadAllBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'All $count lists will be downloaded again from their servers. This can take several minutes.',
      one:
          'The list will be downloaded again from its server. This can take several minutes.',
    );
    return '$_temp0';
  }

  @override
  String reloadAllBodyRecent(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count lists will be downloaded again from their servers.',
      one: 'The list will be downloaded again from its server.',
    );
    return '$_temp0\n\nAlready up to date (less than 24 h): $names.\n\nThis can take several minutes.';
  }

  @override
  String get reloadAllConfirm => 'Reload all';

  @override
  String get reloadAllProgressTitle => 'Reloading';

  @override
  String get reloadAllBackground => 'Continue in the background';

  @override
  String get reloadAllPreparing => 'Preparing…';

  @override
  String reloadAllStep(int index, int total, String label) {
    return 'List $index/$total — $label';
  }

  @override
  String get reloadAllTooltip => 'Reload all lists';

  @override
  String get reloadAllNoAccounts => 'No list to reload';

  @override
  String get infoSectionTitle => 'Details';

  @override
  String get infoGenre => 'Genre';

  @override
  String get infoDirector => 'Director';

  @override
  String get infoCreator => 'Creator';

  @override
  String get infoOriginalTitle => 'Original title';

  @override
  String get infoCountry => 'Country';

  @override
  String get infoStudios => 'Studios';

  @override
  String get infoStatus => 'Status';

  @override
  String get infoRuntime => 'Runtime';

  @override
  String get infoEpisodeLength => 'Episode';

  @override
  String get infoSeasons => 'Seasons';

  @override
  String get infoNextEpisode => 'Next episode';

  @override
  String get infoNetwork => 'Network';

  @override
  String get infoBudget => 'Budget';

  @override
  String get infoRevenue => 'Box office';

  @override
  String get infoTheatrical => 'Theatrical release';

  @override
  String get infoDigital => 'Digital release';

  @override
  String infoSeasonsValue(int seasons, int episodes) {
    String _temp0 = intl.Intl.pluralLogic(
      episodes,
      locale: localeName,
      other: '$episodes episodes',
      one: '1 episode',
    );
    return '$seasons ($_temp0)';
  }

  @override
  String get settingsReloadAllSub =>
      'Re-download all your lists from their servers';

  @override
  String get perfProfileConfort => 'Full';

  @override
  String get perfProfileEquilibre => 'Balanced';

  @override
  String get perfProfilePerformance => 'Light';

  @override
  String get autoProfileOk => 'Got it';

  @override
  String get capsTitle => 'What your device can do';

  @override
  String get capsSub => 'Decoders, display, memory — measured, not guessed';

  @override
  String get capsMeasure => 'Measure again';

  @override
  String get capsNever => 'Not measured yet';

  @override
  String get capsDisplay => 'Display';

  @override
  String get capsMemory => 'Memory';

  @override
  String get capsDecoders => 'Video decoders';

  @override
  String get capsVerdict4k => '4K films';

  @override
  String get capsHardware => 'hardware';

  @override
  String get capsSoftware => 'software';

  @override
  String get capsNoDecoder => 'no decoder';

  @override
  String get capsYes => 'Yes';

  @override
  String get capsNoDecoder4k => 'No — no decoder accepts 2160p';

  @override
  String get capsNoDisplay4k => 'No — the display shows less than 2160p';

  @override
  String get capsUnknown => 'Unknown — incomplete measurement';

  @override
  String get capsLowRam => 'low-memory device';

  @override
  String get refuse4kTitle => 'This 4K version can\'t play here';

  @override
  String get refuse4kDecoder =>
      'No decoder on this device accepts a 3840×2160 picture. Pick an FHD or HD version.';

  @override
  String refuse4kDisplay(int w, int h) {
    return 'The display shows $w×$h: 4K would be decoded for nothing and may stutter. Pick an FHD or HD version.';
  }

  @override
  String get refuseOk => 'Got it';

  @override
  String autoProfileTitle(String name) {
    return '$name profile chosen for this device';
  }

  @override
  String autoProfileBody(String name, int ram, int cores) {
    return 'Based on the measurement ($ram MB of memory, $cores cores), the home uses the $name profile. You can change it anytime in Settings → Optimisation.';
  }

  @override
  String capsMeasuredAt(String date) {
    return 'Measured on $date';
  }

  @override
  String capsDisplayValue(int w, int h, int hz) {
    return '$w×$h at $hz Hz';
  }

  @override
  String capsMemoryValue(int total, int avail) {
    return '$total MB total, $avail MB free';
  }

  @override
  String capsDecoderValue(String name, String kind, int w, int h) {
    return '$name ($kind) — up to $w×$h';
  }

  @override
  String get perfProfileConfortSub => 'All animations';

  @override
  String get perfProfileEquilibreSub => 'Static hero, shorter rows';

  @override
  String get perfProfilePerformanceSub => 'Low memory';

  @override
  String get tmdbRowsProvidersTitle => 'Netflix, Disney+ and Prime trends';

  @override
  String get tmdbRowsProvidersSub =>
      'What\'s popular right now on each platform in France, from your lists';

  @override
  String rowProviderTrending(String name) {
    return 'Trending on $name';
  }

  @override
  String get perfDownloadsSection => 'Downloads';

  @override
  String get perfParallelDownloadsTitle => 'Downloads at once';

  @override
  String get perfParallelDownloadsSub =>
      'One transfer at a time per subscription: providers accept a single connection, and the player keeps one. This number only applies across different subscriptions; the others wait their turn.';

  @override
  String get taskStatusQueuedWhy =>
      'Waiting: one transfer at a time per subscription';

  @override
  String get perfWifiOnlyTitle => 'Download on Wi-Fi only';

  @override
  String get perfWifiOnlySub =>
      'On mobile data (or a metered hotspot), transfers wait and resume on their own as soon as Wi-Fi or a wired connection is back.';

  @override
  String get taskStatusWaitWifi => 'Waiting for Wi-Fi (metered network)';

  @override
  String get taskStatusWaitNetwork => 'Waiting for network';

  @override
  String get offlineBannerTitle =>
      'Offline — only downloaded files can be played';

  @override
  String get offlineBannerRetry => 'Retry';

  @override
  String get offlineBootMessage =>
      'No network to load your lists. Your downloaded files are still here; the app will resume on its own as soon as the connection is back.';

  @override
  String capsDisplayModesNote(int w, int h) {
    return 'The screen reports up to $w×$h. Android renders the UI smaller; video plays at native size.';
  }

  @override
  String get capsDisplayUiNote =>
      'What Android reports here describes the UI, not necessarily the panel: many 4K TVs render menus at 1080p and video at 2160p. Only the decoders decide about 4K.';

  @override
  String get perfPurgeNothing => 'Nothing to reclaim — no orphan files';

  @override
  String perfPurgeDone(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '🧹 $size freed ($count files)',
      one: '🧹 $size freed ($count file)',
    );
    return '$_temp0';
  }

  @override
  String get perfResetTitle => 'Reset settings?';

  @override
  String get perfResetQuestion =>
      'All optimization settings return to their default values.';

  @override
  String get perfResetConfirm => 'Reset';

  @override
  String get perfResetDone => 'Settings reset';

  @override
  String perfFreeMemoryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '💤 $count secondary accounts unloaded from memory',
      one: '💤 $count secondary account unloaded from memory',
    );
    return '$_temp0';
  }

  @override
  String get perfFreeMemoryNothing =>
      'Nothing to free (only one account loaded)';

  @override
  String get perfImageCacheCleared => '🧹 Image cache cleared';

  @override
  String get perfSectionProfiles => 'Profiles';

  @override
  String get perfSectionHero => 'Hero banner';

  @override
  String get perfHeroSub =>
      'Stack of cards at the top of the home screen (costly on low-end boxes)';

  @override
  String get perfAutoRotateTitle => 'Automatic rotation';

  @override
  String get perfAutoRotateSub =>
      'Rotates the hero every 6 s (manual swipe still works)';

  @override
  String get perfHeroCardsLabel => 'Cards';

  @override
  String get perfSectionRows => 'Category rows';

  @override
  String get perfItemsLabel => 'Thumbnails';

  @override
  String get perfItemsSub =>
      'Thumbnails shown per row before the “See all” tile (Favorites are never truncated).';

  @override
  String get perfSectionPlayback => 'Playback';

  @override
  String get perfAutoNextTitle => 'Automatic next episode';

  @override
  String get perfAutoNextSub =>
      'Plays the next episode at the end, after a countdown you can cancel. A season change always asks for confirmation.';

  @override
  String get perfBufferLabel => 'Playback buffer';

  @override
  String get perfBufferSub =>
      'Seconds of video kept ahead. Raising it helps with a throttling provider — playback draws from the buffer instead of stalling — but holds that much more stream in memory, which matters on a set-top box. The “Stalls” counter in the Video info panel tells you whether the setting helps. Takes effect on the next playback.';

  @override
  String get perfSectionLists => 'Playlists';

  @override
  String get perfKeepListsTitle => 'Keep every playlist in memory';

  @override
  String get perfKeepListsSub =>
      'Every account stays loaded: search covers all accounts and switching playlists is instant. Uses more memory — turn it off on a Fire Stick or a box that has little.';

  @override
  String get perfUnloadAfterLabel => 'Unload after';

  @override
  String get perfUnloadNever => 'Never';

  @override
  String perfMinutesShort(int count) {
    return '$count min';
  }

  @override
  String get perfUnloadSub =>
      'Minutes without opening a secondary playlist before it leaves memory. “Never” (0) is the same as keeping every playlist.';

  @override
  String get perfSectionMemory => 'Memory & usage';

  @override
  String get perfImageRamLabel => 'Images (RAM)';

  @override
  String get perfImageRamSub =>
      'RAM reserved for images already displayed. Only adjust it if memory is genuinely short.';

  @override
  String get perfFreeMemoryButton => 'Free memory from secondary accounts';

  @override
  String get perfClearImageCacheButton => 'Clear the image cache';

  @override
  String get perfClearImageCacheNote =>
      'Thumbnails are kept on disk to avoid downloading them again. Clear it if a poster changed on the provider side or if storage is running out.';

  @override
  String get perfSectionStorage => 'Storage';

  @override
  String get perfStorageScanning => 'Scanning storage…';

  @override
  String get perfStorageNothing =>
      'Nothing to reclaim: every file belongs to an existing account.';

  @override
  String perfStorageReclaimable(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$size taken by $count files nothing needs any more: lists from deleted accounts, and interrupted downloads that can no longer resume.',
      one:
          '$size taken by $count file nothing needs any more: lists from deleted accounts, and interrupted downloads that can no longer resume.',
    );
    return '$_temp0';
  }

  @override
  String get perfPurging => 'Cleaning…';

  @override
  String get perfPurgeButton => 'Clean up orphan files';

  @override
  String get perfUnitSeconds => ' s';

  @override
  String get perfUnitMegabytes => ' MB';

  @override
  String get acctAddHowTitle => 'How do you want to add a playlist?';

  @override
  String get acctAddFromPhone => 'From my phone';

  @override
  String get acctAddFromPhoneSub =>
      'Recommended — QR code to the full panel (add, edit, reload)';

  @override
  String get acctAddWithRemote => 'With the remote';

  @override
  String get acctAddWithRemoteSub => 'Key-by-key typing';

  @override
  String acctDeleteBody(String label) {
    return '“$label” and its credentials will be erased permanently.';
  }

  @override
  String acctDeleteListGone(String size) {
    return 'The downloaded playlist goes with it ($size freed).';
  }

  @override
  String get acctDeleteNoList =>
      'No downloaded playlist to erase for this account.';

  @override
  String get acctDeleteKept =>
      'Favorites, resume points and finished downloads are kept.';

  @override
  String acctDeletedWithSize(String label, String size) {
    return '✅ “$label” deleted — $size freed';
  }

  @override
  String acctDeleted(String label) {
    return '✅ “$label” deleted';
  }

  @override
  String get acctAdd => 'Add';

  @override
  String get acctEmptyTitle => 'No account set up';

  @override
  String get acctEmptySubTv =>
      'Scan the QR code with your phone to set up your playlist without typing on the D-pad.';

  @override
  String get acctEmptySubPhone =>
      'Add a full M3U URL or an Xtream Codes account to start streaming.';

  @override
  String get acctEmptyCtaTv => 'Set up from my phone';

  @override
  String get acctEmptyCtaPhone => 'Add a playlist';

  @override
  String get acctMainAccount => 'MAIN ACCOUNT';

  @override
  String acctListsCount(int count) {
    return '$count playlists';
  }

  @override
  String acctStatusInProgress(int loaded, int total, int inProgress) {
    return '$loaded/$total · $inProgress in progress…';
  }

  @override
  String acctStatusWithFailed(String base, int failed) {
    return '$base · $failed failed';
  }

  @override
  String acctStatusFailed(int loaded, int total, int failed) {
    return '$loaded/$total · $failed failed';
  }

  @override
  String acctStatusLoaded(int loaded, int total) {
    return '✓ $loaded/$total loaded';
  }

  @override
  String acctReloadedFor(String label) {
    return '✅ Playlist reloaded for $label';
  }

  @override
  String commonFailedWith(String reason) {
    return '❌ Failed: $reason';
  }

  @override
  String get acctReloadTitle => 'Reload?';

  @override
  String acctReloadBody(String label, String age) {
    return 'The playlist for “$label” was downloaded $age ago.\nReload it from the server anyway?';
  }

  @override
  String get acctReload => 'Reload';

  @override
  String get acctDownloading => 'Downloading…';

  @override
  String get acctReloadPlaylist => 'Reload the playlist';

  @override
  String get acctChipAvailable => 'AVAILABLE';

  @override
  String get acctChipDownloading => 'DOWNLOADING…';

  @override
  String get acctChipLoading => 'LOADING…';

  @override
  String get acctChipError => 'ERROR';

  @override
  String get acctChipNotLoaded => 'NOT LOADED';

  @override
  String get acctChipExpired => 'EXPIRED';

  @override
  String get acctChipExpiresToday => 'EXPIRES TODAY';

  @override
  String acctChipExpiresIn(int days) {
    return 'EXPIRES IN $days D';
  }

  @override
  String get acctCountFilms => 'Movies';

  @override
  String get acctCountSeries => 'Series';

  @override
  String get acctCountTv => 'Channels';

  @override
  String acctStartupTime(String seconds) {
    return 'start $seconds s';
  }

  @override
  String get acctM3uSize => 'M3U size';

  @override
  String get acctCacheAge => 'Cache age';

  @override
  String get acctNoCache => 'No cache';

  @override
  String get acctAgeJustNow => 'just now';

  @override
  String acctAgeMinutes(int count) {
    return '$count min ago';
  }

  @override
  String acctAgeHours(int count) {
    return '${count}h ago';
  }

  @override
  String acctAgeDays(int count) {
    return '$count d ago';
  }

  @override
  String get acctXtreamLoading => 'Reading Xtream info…';

  @override
  String get acctXtreamUnavailable => 'Xtream info unavailable';

  @override
  String get acctExpiration => 'Expiry';

  @override
  String get acctConnections => 'Connections';

  @override
  String get acctExpiryUnknown => 'Unknown';

  @override
  String acctExpiryPast(int days) {
    return 'Expired ($days d)';
  }

  @override
  String get acctExpiryToday => 'Expires today';

  @override
  String get acctExpiryTomorrow => 'Expires tomorrow';

  @override
  String acctExpiryInDays(int days) {
    return 'In $days days';
  }

  @override
  String unitBytes(String value) {
    return '$value B';
  }

  @override
  String unitKilobytes(String value) {
    return '$value kB';
  }

  @override
  String unitMegabytes(String value) {
    return '$value MB';
  }

  @override
  String unitGigabytes(String value) {
    return '$value GB';
  }

  @override
  String acctAgeHoursMinutes(int hours, String minutes) {
    return '${hours}h$minutes';
  }

  @override
  String acctAgeMinutesShort(int count) {
    return '${count}m';
  }

  @override
  String get homeExitSearch => 'Leave search';

  @override
  String get homeSearchHint => 'Search the playlist…';

  @override
  String get homeTabSeries => 'Series';

  @override
  String get homeTabMovies => 'Movies';

  @override
  String get homeTabTv => 'Channels';

  @override
  String get homeEmptyMovies => 'No movies';

  @override
  String get homeEmptySeries => 'No series';

  @override
  String get homeEmptyTv => 'No channels';

  @override
  String get homeEmptySub =>
      'None of your playlists contains any. Reload a playlist or add an account.';

  @override
  String get homeEmptyCta => 'Manage accounts';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeResume => 'RESUME';

  @override
  String get homeResumeChannel => 'RESUME CHANNEL';

  @override
  String get searchNoTitleFound => 'No title found';

  @override
  String searchNoTitleSub(String query) {
    return 'Nothing in your playlists for “$query”. Try another keyword or check the spelling.';
  }

  @override
  String get searchKeepTyping => 'Keep typing…';

  @override
  String searchKeepTypingSub(int count) {
    return 'At least $count letters to search a movie or a series. Channels can be searched from the very first letter.';
  }

  @override
  String searchFromPerson(String name) {
    return 'By $name, in your playlists';
  }

  @override
  String get searchOnTmdbMissing => 'On TMDB, missing from your playlists';

  @override
  String get searchNotAvailable => 'NOT AVAILABLE';

  @override
  String get searchTypeToSearch => 'Type to search your playlist';

  @override
  String get searchTypesLine => 'Movies · Series · Channels';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchClearHistoryTitle => 'Clear history?';

  @override
  String get searchClearHistoryOne => 'The last search will be removed.';

  @override
  String searchClearHistoryMany(int count) {
    return 'The last $count searches will be removed.';
  }

  @override
  String get searchClearConfirm => 'Clear';

  @override
  String get searchHistoryCleared => 'History cleared';

  @override
  String get cardPlay => 'Play';

  @override
  String cardResumeFrom(String position) {
    return 'Resume from $position';
  }

  @override
  String get cardPlayFromStart => 'Play from the start';

  @override
  String get cardForgetResume => 'Forget the resume point';

  @override
  String get cardForgetResumeTitle => 'Forget the resume point?';

  @override
  String get cardForgetResumeQuestion =>
      'The playback position for this title will be forgotten.';

  @override
  String get cardForgetConfirm => 'Forget';

  @override
  String get cardResumeForgotten => 'Resume point forgotten';

  @override
  String get cardDetails => 'See details';

  @override
  String get castChannelsStereo => 'stereo';

  @override
  String get castChannelsMono => 'mono';

  @override
  String castChannelsCount(int count) {
    return '$count channels';
  }

  @override
  String get castAudioTrackFallback => 'Audio track';

  @override
  String castAudioWarnPartial(String track) {
    return 'The TV will not decode every track of this stream. The app will ask it for: $track. If the sound is still missing, the receiver kept its default track.';
  }

  @override
  String castAudioWarnSingle(String detail) {
    return 'The sound of this stream is $detail: the TV receiver cannot decode it (picture without sound). The app cannot convert it.';
  }

  @override
  String castAudioWarnNone(String detail) {
    return 'No audio track of this stream can be decoded by the TV receiver ($detail): picture without sound. Another version of the same title, in AAC, would work.';
  }

  @override
  String get castReceiverNoTracks => 'no track announced';

  @override
  String castReceiverNoAudio(int count) {
    return '$count track(s), no audio';
  }

  @override
  String castReceiverAudioSummary(int count, String labels) {
    return '$count audio: $labels';
  }

  @override
  String get castNoWifi =>
      'The phone is not on a Wi-Fi network: the Chromecast cannot fetch the file. Connect it to the same network as the TV.';

  @override
  String get castNotStreamable =>
      'This address cannot be cast (neither http nor https).';

  @override
  String get castCannotVerify =>
      'The stream cannot be checked from this network. Try again in a moment.';

  @override
  String get castTlsRefused =>
      'The provider uses a certificate the Chromecast refuses (the app accepts it). This stream cannot be cast.';

  @override
  String get castUnreachable =>
      'The provider\'s server does not answer from this network.';

  @override
  String get castNeedsAuth =>
      'This stream cannot be cast: the provider requires an identification the Chromecast cannot pass on.';

  @override
  String get castNotHls =>
      'The provider does not offer this stream in a format the Chromecast can read (HLS).';

  @override
  String castHttpRefused(int code) {
    return 'This stream cannot be cast: the provider refuses a request without the app\'s IPTV profile (HTTP response $code), which the Chromecast cannot imitate.';
  }

  @override
  String get castNoCors =>
      'This stream cannot be cast: the provider does not allow playback from a browser (no CORS header), and that is how the Chromecast reads HLS.';

  @override
  String castNoticePlaying(String device) {
    return 'Casting to $device';
  }

  @override
  String castNoticePaused(String device) {
    return 'Paused on $device';
  }

  @override
  String get castIdleFinished => 'Playback finished on the TV.';

  @override
  String get castIdleError =>
      'The TV could not play this stream (format or address refused by the receiver).';

  @override
  String get castIdleInterrupted => 'Casting interrupted by the TV.';

  @override
  String get perrTimedOut => 'The stream stopped responding (timed out).';

  @override
  String get perrConnectionFailed =>
      'Cannot connect to the server. Check your network.';

  @override
  String get perrConnectionTimeout => 'The server took too long to answer.';

  @override
  String get perrBadHttpStatus =>
      'The server refused the stream (HTTP error). Check the account or try again later.';

  @override
  String get perrFileNotFound => 'Stream not found on the server.';

  @override
  String get perrNoPermission => 'Access to the stream refused.';

  @override
  String get perrCleartextNotPermitted =>
      'Unencrypted connection refused by the system.';

  @override
  String get perrInvalidContentType =>
      'The server is not returning a video (unexpected content type).';

  @override
  String get perrPositionOutOfRange => 'Playback position outside the stream.';

  @override
  String get perrNetwork => 'Network playback error.';

  @override
  String get perrBehindLiveWindow =>
      'Too far behind the live edge: jumping back to live.';

  @override
  String get perrPlayerTimeout => 'The player did not answer in time.';

  @override
  String get perrMalformed =>
      'Unreadable stream (corrupted or unexpected data).';

  @override
  String get perrUnsupportedFormat => 'Stream format not supported.';

  @override
  String get perrDecoderInit => 'Cannot initialize the video decoder.';

  @override
  String get perrDecoderReclaimed =>
      'The system reclaimed the video decoder. Close other apps, then start playback again.';

  @override
  String get perrDecodingFailed =>
      'Decoding failed: the stream may be damaged.';

  @override
  String get perrExceedsCapabilities =>
      'This stream exceeds the device capabilities (resolution or bitrate).';

  @override
  String get perrCodecUnsupported => 'Codec not supported by this device.';

  @override
  String get perrAudioOutput =>
      'Audio output unavailable (track or audio format not playable).';

  @override
  String get perrRemote => 'Remote player error.';

  @override
  String get perrUnexpected => 'The player hit an unexpected error.';

  @override
  String get perrDrm => 'Protected content (DRM) cannot be played.';

  @override
  String get perrDecodeVideo => 'Video decoding failed.';

  @override
  String get perrCannotPlay => 'Playback failed.';

  @override
  String perrCannotPlayWith(String detail) {
    return 'Playback failed: $detail';
  }

  @override
  String get relayBatteryPluggedOk =>
      'The phone is plugged in, perfect for a movie.';

  @override
  String get relayBatteryPlugIfYouCan =>
      'Plug the phone in if you can: converting uses a lot of battery.';

  @override
  String relayBatteryLow(int percent) {
    return 'Battery at $percent% — plug the phone in, casting depends on it.';
  }

  @override
  String relayBatteryMid(int percent) {
    return 'Battery at $percent%. Plug the phone in if you can, converting uses a lot of battery.';
  }

  @override
  String get relayScreenOffOk =>
      'You can turn the screen off: casting continues in the background.';

  @override
  String get relayDeviceFallback => 'the TV';

  @override
  String relayConsentWhat(String device) {
    return 'This TV cannot play the sound of this movie. The phone can adapt it while casting to $device.';
  }

  @override
  String get relayConsentConfirm => 'Adapt and cast';

  @override
  String get playerLastEpisode => 'Last available episode.';

  @override
  String playerAudioTrackSwitched(String track) {
    return 'Incompatible audio track — switching to $track';
  }

  @override
  String get playerNoAudioTrack =>
      'No playable audio track in this file — playing without sound';

  @override
  String playerReconnecting(int attempt, int max) {
    return 'Reconnecting in 5 s… ($attempt/$max)';
  }

  @override
  String get playerRetry => 'Try again';

  @override
  String get playerBuffering => 'Buffering…';

  @override
  String get castOverlayBack => 'Back (casting continues)';

  @override
  String castOverlayCastingOn(String device) {
    return 'CASTING TO $device';
  }

  @override
  String get castOverlayStarting => 'Starting on the TV…';

  @override
  String castOverlayPlayingAt(String position) {
    return 'Playing · $position';
  }

  @override
  String get castOverlayLoading => 'Loading on the TV…';

  @override
  String get castOverlayBack30 => 'Back 30 s';

  @override
  String get castOverlayPause => 'Pause';

  @override
  String get castOverlayPlay => 'Play';

  @override
  String get castOverlayForward30 => 'Forward 30 s';

  @override
  String castOverlayReceiver(String detail) {
    return 'Receiver · $detail';
  }

  @override
  String castOverlayCastTitle(String title) {
    return 'Cast “$title”';
  }

  @override
  String get castOverlayResync => 'Resynchronize picture and sound';

  @override
  String get castOverlayResumeHere => 'Resume on the phone';

  @override
  String get castOverlaySoundConverted => 'Sound fully converted';

  @override
  String get castOverlaySoundConverting => 'Converting the sound';

  @override
  String get castOverlayTvPlaysWhileConverting =>
      'The TV plays while converting. Keep the app open.';

  @override
  String castOverlayPreparingFor(String device) {
    return 'PREPARING FOR $device';
  }

  @override
  String get castOverlayCancelConversion => 'Cancel the conversion';

  @override
  String get castSheetNotCastable => 'This stream cannot be cast.';

  @override
  String castSheetOnDevice(String device) {
    return 'On $device';
  }

  @override
  String get castSheetTitle => 'Cast to…';

  @override
  String get castSheetSearching => 'Looking for devices on the network…';

  @override
  String castSheetChecking(String device) {
    return 'Checking the stream for $device…';
  }

  @override
  String get castSheetChooseOther => 'Choose another device';

  @override
  String get castSheetConvertSound => 'Convert the sound on the phone';

  @override
  String get castSheetConvertSoundSub => 'See what it involves before starting';

  @override
  String get castSheetCastAnyway => 'Cast anyway';

  @override
  String castSheetCastAnywaySub(String device) {
    return 'On $device — picture without sound';
  }

  @override
  String get castSheetStop => 'Stop casting';

  @override
  String castSheetStopSub(String device) {
    return 'Running on $device';
  }

  @override
  String get castSheetNothingFound =>
      'No Chromecast found. The phone must be on the same Wi-Fi as the TV, outside a guest network.';

  @override
  String get castSheetSearchAgain => 'Search again';

  @override
  String get tracksNoAudio => 'No audio track detected';

  @override
  String get tracksNoSubtitles => 'No subtitle detected';

  @override
  String get tracksNone => 'None';

  @override
  String get tracksDisabled => 'Disabled';

  @override
  String get langFrench => 'French';

  @override
  String get langEnglish => 'English';

  @override
  String get langSpanish => 'Spanish';

  @override
  String get langGerman => 'German';

  @override
  String get langItalian => 'Italian';

  @override
  String get langPortuguese => 'Portuguese';

  @override
  String get langArabic => 'Arabic';

  @override
  String get langRussian => 'Russian';

  @override
  String get langDutch => 'Dutch';

  @override
  String get langJapanese => 'Japanese';

  @override
  String get langChinese => 'Chinese';

  @override
  String get langKorean => 'Korean';

  @override
  String get langTurkish => 'Turkish';

  @override
  String get langPolish => 'Polish';

  @override
  String get statsDecoding => 'Decoding';

  @override
  String statsHardwareWith(String decoder) {
    return 'hardware · $decoder';
  }

  @override
  String get statsHardware => 'hardware';

  @override
  String get statsResolution => 'Resolution';

  @override
  String statsAnnouncedOversold(String announced) {
    return '$announced — the playlist OVERSELLS';
  }

  @override
  String statsAnnouncedBetter(String announced) {
    return '$announced · better than promised';
  }

  @override
  String get statsYes => 'yes';

  @override
  String get statsNo => 'no';

  @override
  String get statsDropped => 'Skipped';

  @override
  String get statsBitrate => 'Bitrate';

  @override
  String get statsNetwork => 'Network';

  @override
  String get statsTransferred => 'Transferred';

  @override
  String get statsStartup => 'Startup';

  @override
  String get statsChannelsStereo => 'stereo';

  @override
  String get statsChannelsMono => 'mono';

  @override
  String statsChannelsCount(int count) {
    return '$count channels';
  }

  @override
  String get statsStallsNone => 'none';

  @override
  String statsStallsWithTime(int count, int seconds) {
    return '$count (${seconds}s in total)';
  }

  @override
  String get nextEpLoading => 'Loading the next episode…';

  @override
  String get nextEpTitle => 'NEXT EPISODE';

  @override
  String get nextEpPlay => 'Play';

  @override
  String get nextEpSeasonEnd => 'END OF SEASON';

  @override
  String nextEpGoToSeason(int season) {
    return 'Go to season $season?';
  }

  @override
  String get nextEpGoToNextSeason => 'Go to the next season?';

  @override
  String get nextEpBackToDetails => 'Back to the details';

  @override
  String get nextEpSeriesOver => 'SERIES FINISHED';

  @override
  String get nextEpSeriesOverSub =>
      'You have watched the last available episode.';

  @override
  String get ctrlCast => 'Cast to a Chromecast';

  @override
  String get ctrlPip => 'Shrink to a window';

  @override
  String get ctrlOptions => 'Playback options';

  @override
  String get ctrlTracks => 'Audio and subtitle tracks';

  @override
  String get ctrlSpeed => 'Playback speed';

  @override
  String get ctrlNextEpisode => 'Next episode';

  @override
  String get ctrlBadgeMovie => 'MOVIE';

  @override
  String get ctrlBadgeSeries => 'SERIES';

  @override
  String get ctrlUnlock => 'Unlock';

  @override
  String get optNextEpisodeSub => 'Skip to the next episode';

  @override
  String get optTracksSub => 'Audio language · turn subtitles on';

  @override
  String get optVideoInfo => 'Video info';

  @override
  String get optVideoInfoOn => 'Shown · tap to hide';

  @override
  String get optVideoInfoSub => 'Decoding, resolution, frames/s, drops';

  @override
  String get fitContainSub => 'Whole picture · black bars possible';

  @override
  String get fitCoverSub => 'Removes black bars · crops the edges';

  @override
  String get fitFill => 'Full screen';

  @override
  String get fitFillSub => 'Fills everything · slightly distorted picture';

  @override
  String get ctrlCastActive => 'Casting';

  @override
  String get ctrlLock => 'Lock';

  @override
  String get ctrlBadgeLive => 'LIVE';

  @override
  String get ctrlBadgeReplay => 'REPLAY';

  @override
  String get optTitle => 'Options';

  @override
  String get optBackToVideo => 'Back to video';

  @override
  String get sheetClose => 'Close';

  @override
  String get bootSlowHint =>
      'Loading is taking longer than usual. You can go in now: your lists will finish loading in the background.';

  @override
  String get bootContinueAnyway => 'Go in without waiting';

  @override
  String get bootStalledBody =>
      'The main list has stopped making progress. It keeps loading in the background: try again in a moment, or check the account.';

  @override
  String get playlistNoTitles =>
      'This list contains no titles. Check the account, or try again later.';

  @override
  String get sheetCloseSub => 'Closes without changing anything';

  @override
  String get optBackToVideoSub => 'Closes this panel, playback continues';

  @override
  String get optNextEpisode => 'Next episode';

  @override
  String get optTracksTitle => 'Audio & subtitle tracks';

  @override
  String get optSpeedTitle => 'Speed';

  @override
  String get optFitTitle => 'Picture format';

  @override
  String get optSpeedNormal => '1.0×  ·  Normal';

  @override
  String get castSheetDeviceFallback => 'the TV';

  @override
  String get statsDecodingPending => 'in progress…';

  @override
  String get statsSoftware => 'SOFTWARE';

  @override
  String get statsOutput => 'Output';

  @override
  String get statsCodec => 'Codec';

  @override
  String get statsHdr => 'HDR';

  @override
  String get statsFps => 'Frames/s';

  @override
  String get statsLost => 'Lost';

  @override
  String get statsRendered => 'Rendered';

  @override
  String get statsBuffer => 'Buffer';

  @override
  String get statsAudio => 'Audio';

  @override
  String get statsStalls => 'Stalls';

  @override
  String statsAnnouncedOk(String announced) {
    return '$announced · as promised';
  }

  @override
  String statsRenderedValue(String fps) {
    return '$fps fps';
  }

  @override
  String statsRenderedVsAnnounced(String fps, String announced) {
    return '$fps fps (announced $announced)';
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
    return 'Resuming playback… ($attempt/$max)';
  }

  @override
  String get playerOtherTrack => 'another track';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonApplying => 'Applying…';

  @override
  String get bkPasswordTitle => 'Encryption password';

  @override
  String get bkPasswordHelp =>
      'Choose a password — it will be asked for to restore the backup.';

  @override
  String get bkPasswordLabel => 'Password';

  @override
  String get bkPasswordConfirmLabel => 'Confirm';

  @override
  String get bkPasswordEmpty => 'The password cannot be empty.';

  @override
  String get bkPasswordTooShort => 'At least 6 characters.';

  @override
  String get bkPasswordMismatch => 'The two passwords differ.';

  @override
  String get bkSave => 'Back up';

  @override
  String get bkCreated => 'Backup created';

  @override
  String get bkCreateTitle => 'Create a backup';

  @override
  String get bkCreateSub =>
      'Encrypts your accounts, TMDB key, theme, favorites and progress into a .aether file.';

  @override
  String get bkEncrypting => 'Encrypting…';

  @override
  String get bkRestoreTitle => 'Restore a backup';

  @override
  String get bkRestoreSub =>
      'Pick a .aether file, enter your password, check the summary, apply.';

  @override
  String get bkRestoring => 'Restoring…';

  @override
  String get bkImportFile => 'Import a .aether file';

  @override
  String get bkHowTitle => 'How it works';

  @override
  String get bkHowBody =>
      '• `.aether` file encrypted with AES-256-GCM + PBKDF2 (100k iterations).\n• Password chosen by you — the app stores it nowhere.\n• Location: Download/AetherStream/ (survives an uninstall).\n• Contents: IPTV accounts, TMDB key, theme, favorites, progress.\n• Excluded: downloads (too heavy), search history.\n• Importing overwrites the whole current configuration (irreversible).';

  @override
  String get bkRestorePasswordTitle => 'Backup password';

  @override
  String get bkDecrypt => 'Decrypt';

  @override
  String get bkConfirmRestoreTitle => 'Confirm the restore';

  @override
  String get bkConfirmRestoreBody =>
      'Your whole current state (accounts, TMDB key, theme, favorites, playback progress) will be OVERWRITTEN by this backup.\n\nThis cannot be undone. Continue?';

  @override
  String get bkRestore => 'Restore';

  @override
  String get bkRestoreDone => 'Restore succeeded';

  @override
  String get bkRestoreDoneSub =>
      'The IPTV playlists will be downloaded again on the next start.';

  @override
  String get regionApplied => '✅ Filter applied — catalog reloaded';

  @override
  String get regionHelp =>
      'Tick the languages/regions to HIDE from the catalog. French (|FR|), Québécois and VOSTFR content is always kept.';

  @override
  String get regionApplying => 'Applying the filter…';

  @override
  String get regionApplyingSub =>
      'The catalog is being re-parsed. This may take a few seconds.';

  @override
  String get regionHidden => 'Hidden';

  @override
  String get regionVisible => 'Visible';

  @override
  String get bkExportLocation =>
      'Available in:\n/storage/emulated/0/Download/AetherStream/\n\nCopy this file to Drive, your PC, or another device to restore it later. Do not forget the password — it is stored nowhere.';

  @override
  String get themeResetTitle => 'Reset the theme?';

  @override
  String get themeResetQuestion =>
      'Every color and effect returns to its default value.';

  @override
  String get themeSectionPresets => 'Presets';

  @override
  String get themeSectionColors => 'Colors';

  @override
  String get themeColorPrimary => 'Primary';

  @override
  String get themeColorAccent => 'Accent';

  @override
  String get themeColorTertiary => 'Tertiary';

  @override
  String get themeSectionStateColors => 'State colors';

  @override
  String get themeColorFavorite => 'Favorite ❤';

  @override
  String get themeColorWarning => 'Resume / Alert';

  @override
  String get themeColorError => 'Error';

  @override
  String get themeColorSuccess => 'Success';

  @override
  String get themeSectionEffects => 'Effects';

  @override
  String get themeGlow => 'Glow';

  @override
  String get themeRadius => 'Corner radius';

  @override
  String get themeSectionMode => 'Mode';

  @override
  String get themeSectionPreview => 'Preview';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themePreviewPlay => '▶  Play';

  @override
  String get xmltvUpdated => '✅ Channel guide updated';

  @override
  String get xmltvUpdateUnavailable =>
      'The channel guide couldn\'t be updated right now. Try again later.';

  @override
  String xmltvUpdateFailed(String reason) {
    return '❌ Update failed: $reason';
  }

  @override
  String get xmltvNeverLoaded => 'Never loaded';

  @override
  String get xmltvJustNow => 'Just now';

  @override
  String xmltvChannelsAndAge(int count, String age) {
    return '$count channels · $age';
  }

  @override
  String get xmltvDownloading => 'Downloading…';

  @override
  String get xmltvForceUpdate => 'Force an update';

  @override
  String get xmltvHowBody =>
      '• Public source: xmltvfr.fr (French DTT)\n• Covers the main French channels (TF1, France 2, M6, ARTE…)\n• Used for the “Now / Next” block and the replay grid';

  @override
  String visualLangApplied(String language) {
    return 'Artwork in $language — posters already on screen keep their language until the next reload.';
  }

  @override
  String get visualLangUiStaysFrench =>
      'Posters, backdrops and texts coming from TMDB. The app interface follows the device language.';

  @override
  String get visualLangNote =>
      'A poster provided by your IPTV playlist is never replaced: this choice only applies to artwork the app fetches itself.';

  @override
  String get aboutChecking => '🔍 Checking for updates…';

  @override
  String get aboutUpToDate => 'You are up to date.';

  @override
  String aboutCheckFailed(String reason) {
    return '⚠️ Cannot check: $reason';
  }

  @override
  String get aboutTagline =>
      'Android IPTV client — multi-account, EPG, replay, TMDB.';

  @override
  String get aboutCheckingShort => 'Checking…';

  @override
  String get aboutCheckUpdates => 'Check for updates';

  @override
  String get consoleNoNetwork =>
      'No local network found. Connect the TV to Wi-Fi or Ethernet.';

  @override
  String consoleStartFailed(String reason) {
    return 'Cannot start the local server: $reason';
  }

  @override
  String get consoleOpenAddress =>
      'Open this address in a browser\non a PC or a phone on the same network:';

  @override
  String get consoleAddressCopied => 'Address copied';

  @override
  String get consoleBackgroundNote =>
      'The server stays alive in the background as long as you use the remote, even after leaving this screen. Stop it here when you are done (otherwise it closes after 30 min without use).';

  @override
  String get consoleStopServer => 'Stop the server';

  @override
  String get consoleActiveBanner =>
      'Web console open: the app can be controlled from your local network';

  @override
  String get failNotLoaded => 'NOT LOADED';

  @override
  String get failNetwork => 'NETWORK FAILED';

  @override
  String get failPanelBusy => 'PANEL BUSY';

  @override
  String get failIncomplete => 'INCOMPLETE LIST';

  @override
  String get failParse => 'PARSING FAILED';

  @override
  String get failNoData => 'NO DATA';

  @override
  String get failExplainNever => 'This playlist has not been loaded yet.';

  @override
  String get failExplainUnloaded =>
      'Memory freed; the playlist comes back as soon as it is needed.';

  @override
  String get failExplainDeferred => 'Update postponed until after start-up.';

  @override
  String get failExplainPanelBusy =>
      'The provider refused: too many simultaneous connections.';

  @override
  String get failExplainIncomplete =>
      'The catalog arrived incomplete; the previous one was kept.';

  @override
  String get failExplainParse => 'The playlist could not be parsed.';

  @override
  String get failExplainCacheGone => 'The parsed cache is unreadable.';

  @override
  String get failExplainNoSource => 'No cached data for this playlist.';

  @override
  String reloadBatchAllOk(int count) {
    return '✅ $count playlist(s) reloaded';
  }

  @override
  String reloadBatchAllFailed(String names) {
    return '❌ No playlist reloaded — $names';
  }

  @override
  String reloadBatchMixed(int ok, int failed, String names) {
    return '⚠️ $ok reloaded, $failed failed: $names';
  }

  @override
  String get reloadDownloadFailed =>
      'Download failed (check the URL or the connection).';

  @override
  String get playlistNotAList =>
      'The server did not return a usable playlist. Check the playlist address.';

  @override
  String get reloadParseFailed => 'Parsing the playlist failed.';

  @override
  String get bkPartTmdbKey => 'TMDB key';

  @override
  String get bkPartTheme => 'theme';

  @override
  String bkPartHiddenRegions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden languages',
      one: '1 hidden language',
    );
    return '$_temp0';
  }

  @override
  String get bkPasswordEmptyError => 'The password cannot be empty.';

  @override
  String get bkNewerVersion =>
      'Backup created by a newer version of the app; an update is required.';

  @override
  String get bkWrongPassword =>
      'Wrong password, or the backup file is corrupted.';

  @override
  String get bkNoReadableAccount =>
      'None of the accounts in this backup could be read: nothing was changed.';

  @override
  String get castDiscoveryFailed =>
      'Discovery failed on this network. The phone must be on the same Wi-Fi as the TV, outside a guest network.';

  @override
  String castDeviceNotResponding(String device) {
    return '$device is not answering. Check that it is on and on the same network.';
  }

  @override
  String castConnectFailed(String device) {
    return 'Cannot connect to $device.';
  }

  @override
  String get castStreamRefused => 'The TV did not accept this stream.';

  @override
  String get castConnectionLost => 'Connection to the TV lost.';

  @override
  String get relayNoNetworkAddress =>
      'No network address: the TV could not reach the phone.';

  @override
  String get relayStartFailed => 'The conversion could not start.';

  @override
  String get relayOpenFailed => 'Cannot open the relay on the local network.';

  @override
  String get relayTooSlow =>
      'The beginning of the movie did not arrive in time: the source is too slow to be converted.';

  @override
  String get dlQueued => 'Queued…';

  @override
  String get dlFinalizing => 'Finalizing…';

  @override
  String dlActiveCount(int count) {
    return '$count downloads';
  }

  @override
  String updGithubHttp(int code) {
    return 'GitHub answered HTTP $code.';
  }

  @override
  String updNoApk(String tag) {
    return 'The latest release ($tag) contains no APK.';
  }

  @override
  String get updTimeout => 'GitHub did not answer in time.';

  @override
  String get updUnreachable => 'Cannot reach GitHub. Check your connection.';

  @override
  String get updInstallDenied => 'Installation permission denied';

  @override
  String updNoApkForDevice(String tag) {
    return 'The latest release ($tag) has no version for this device.';
  }

  @override
  String get updUnverifiable =>
      'This update cannot be verified, so it was not installed.';

  @override
  String get updCorrupted => 'The downloaded update is damaged. Try again.';

  @override
  String get failOnDisk => 'ON DISK';

  @override
  String get failWaiting => 'WAITING';

  @override
  String get failCacheGone => 'CACHE LOST';

  @override
  String get failBadAccount => 'INVALID ACCOUNT';

  @override
  String get failExplainNetwork => 'Server unreachable.';

  @override
  String get failExplainBadAccount => 'Invalid account configuration.';

  @override
  String bkPartAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String get bkPartOptimization => 'optimization';

  @override
  String bkPartFavorites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count favorites',
      one: '1 favorite',
    );
    return '$_temp0';
  }

  @override
  String bkPartProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resume points',
      one: '1 resume point',
    );
    return '$_temp0';
  }

  @override
  String get bkEmpty => 'Empty backup';

  @override
  String get relayFormatFailed =>
      'The conversion failed: the phone cannot read this format back.';

  @override
  String get dlFilterAll => 'All';

  @override
  String get dlFilterActive => 'In progress';

  @override
  String get dlFilterCompleted => 'Finished';

  @override
  String get dlFilterErrors => 'Errors';

  @override
  String get dlSearchHint => 'Search a download';

  @override
  String get dlSearchOpen => 'Search';

  @override
  String get dlSearchClose => 'Close search';

  @override
  String get dlEmptyHint =>
      'Start a download from a movie or series page — it will show up here with its progress.';

  @override
  String get dlNoSearchResult => 'No download matches this search.';

  @override
  String dlNoneInFilter(String filter) {
    return 'No download in “$filter”.';
  }

  @override
  String get dlStopTitle => 'Stop the download?';

  @override
  String get dlStopBody =>
      'What is already downloaded is kept: you will be able to resume where it stopped.';

  @override
  String get dlStop => 'Stop';

  @override
  String get dlActionPlay => 'Play';

  @override
  String get dlActionMonitor => 'See the progress';

  @override
  String get dlActionCancel => 'Stop the download';

  @override
  String get dlActionDelete => 'Delete';

  @override
  String dlRetriedTimes(int count) {
    return 'restarted ×$count';
  }

  @override
  String get dlAlreadyDownloaded => 'Already downloaded';

  @override
  String get dlSee => 'See';

  @override
  String get dlStorageDenied =>
      'Storage permission denied: the download cannot start.';

  @override
  String get dlOpenSettings => 'Open settings';

  @override
  String get bootFailedTitle => 'Start-up interrupted';

  @override
  String get bootFailedBody => 'The app could not load your playlist.';

  @override
  String get bootCheckAccounts => 'Check the accounts';

  @override
  String get bootNoAccountTitle => 'No account set up';

  @override
  String get bootNoAccountTv =>
      'Scan a QR code with your phone to manage your playlists without typing on the remote.';

  @override
  String get bootNoAccountPhone => 'Add an account to get started.';

  @override
  String get bootConfigureFromPhone => 'Set up from my phone';

  @override
  String get bootConfigureAccounts => 'Set up the accounts';

  @override
  String get bootRestoreBackup => 'Restore a backup';

  @override
  String get onbPlaylistSaved => '✅ Playlist saved';

  @override
  String get onbTmdbSaved => '✅ TMDB key saved';

  @override
  String get onbHasBackup => 'I already have a backup (.aether)';

  @override
  String get onbAddPlaylistTitle => 'Add a playlist';

  @override
  String get onbAddPlaylistBody =>
      'Go to ⚙️ Settings → IPTV accounts to enter a full M3U URL OR an Xtream Codes account (server + credentials).';

  @override
  String get onbTmdbTitle => 'Posters and synopses (optional)';

  @override
  String get onbTmdbBody =>
      'Generate a free TMDB Bearer Token on themoviedb.org and paste it into Settings → TMDB API key to enrich your movies and series.';

  @override
  String get onbCardMenuTitle => 'The ⋯ menu on thumbnails';

  @override
  String get onbCardMenuBody =>
      'Long-press a poster — or tap the ⋯ at the top left — to Play, Resume, add to favorites, download or forget a resume point, without opening the details page.';

  @override
  String get onbWelcomeTitle => 'Welcome to AetherStream';

  @override
  String get onbWelcomeBody =>
      'Multi-account IPTV client to watch movies, series and live channels from your subscriptions.';

  @override
  String get onbConfigureFromPhone => 'Set it up from your phone';

  @override
  String get onbQrBody =>
      'Scan this QR code: you can add your playlist, your TMDB key and set up the rest from your browser — typing on the D-pad would be long and tedious.';

  @override
  String get actorNotFound => 'Error: profile not found on TMDB.';

  @override
  String get actorFilmographyDirecting => 'Filmography (Directing)';

  @override
  String get actorFilmographyRoles => 'Filmography (Roles)';

  @override
  String get actorDirector => 'Director';

  @override
  String actorRole(String character) {
    return 'Role: $character';
  }

  @override
  String detActorNotFound(String name) {
    return 'TMDB found no profile for $name.';
  }

  @override
  String get detTmdbPitch =>
      'Posters, synopses and cast. Quick setup by QR code from your phone.';

  @override
  String detSaga(String name) {
    return 'Saga: $name';
  }

  @override
  String get detSameSaga => 'Same saga';

  @override
  String get detSeasons => 'Seasons';

  @override
  String detSeasonsCountOne(int seasons, int episodes) {
    return '$seasons season · $episodes episodes';
  }

  @override
  String detSeasonsCountMany(int seasons, int episodes) {
    return '$seasons seasons · $episodes episodes';
  }

  @override
  String get detLoadingEpisodes => 'Loading episodes…';

  @override
  String detEpisodesError(String reason) {
    return 'Episodes not loaded — $reason.';
  }

  @override
  String get detNoEpisodes => 'No episode available for this series.';

  @override
  String detSeasonNumber(String number) {
    return 'Season $number';
  }

  @override
  String detEpisodesShort(int count) {
    return '$count ep.';
  }

  @override
  String detRealOversold(String definition) {
    return '⚠ actual $definition';
  }

  @override
  String detReal(String definition) {
    return 'actual $definition';
  }

  @override
  String detResumeAt(String position) {
    return 'RESUME · $position';
  }

  @override
  String detFavoriteAdded(String title) {
    return '⭐ “$title” added to favorites';
  }

  @override
  String detFavoriteRemoved(String title) {
    return '🗑️ “$title” removed from favorites';
  }

  @override
  String get detNotInPlaylists =>
      'Not in your playlists — page shown from TMDB.';

  @override
  String get detSearchInPlaylists => 'SEARCH MY PLAYLISTS';

  @override
  String get detStatusReleased => 'Released';

  @override
  String get detStatusPostProduction => 'Post-production';

  @override
  String get detStatusInProduction => 'In production';

  @override
  String get detStatusPlanned => 'Planned';

  @override
  String get detStatusReturning => 'Returning';

  @override
  String get detStatusEnded => 'Ended';

  @override
  String get detStatusCanceled => 'Canceled';

  @override
  String get sheetDetails => 'Details & info';

  @override
  String get sheetReplayUnavailable => 'Replay unavailable for this stream';

  @override
  String get onbSkip => 'Skip';

  @override
  String get onbNext => 'Next';

  @override
  String get onbStart => 'Get started';

  @override
  String termPreviousErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PREVIOUS ERRORS',
      one: '$count PREVIOUS ERROR',
    );
    return '$_temp0';
  }

  @override
  String get replayPickTitle => 'Pick a moment to replay';

  @override
  String get replayQuality => 'Quality';

  @override
  String get replayDay => 'Day';

  @override
  String get replayOrManually => 'OR CHOOSE MANUALLY';

  @override
  String get replayStartTime => 'Start time';

  @override
  String get replayDuration => 'Duration';

  @override
  String replayAtWithDuration(String day, String time, String duration) {
    return '$day at $time ($duration)';
  }

  @override
  String get replayNoEpg => 'No EPG data available';

  @override
  String get replayNoneTitle => 'No replay available';

  @override
  String get replayNoneBody =>
      'This channel exposes no Xtream EPG, or its timeshift is disabled. Try the manual picker from the TV action sheet.';

  @override
  String expExpiredSince(int days, String date) {
    return 'Expired $days days ago ($date)';
  }

  @override
  String expExpiresIn(int days, String date) {
    return 'Expires in $days days ($date)';
  }

  @override
  String get expTitleExpired => 'Playlist expired';

  @override
  String get expTitleSoon => 'Playlist expiring soon';

  @override
  String get expBodyExpired =>
      'This playlist can no longer be used. Renew with your provider to regain access.';

  @override
  String get expBodySoon =>
      'Renew with your provider so you do not lose access.';

  @override
  String get expLater => 'Later';

  @override
  String get expSeeDetails => 'See details';

  @override
  String get memTitle => 'MEMORY & STORAGE';

  @override
  String get memRefresh => 'Refresh';

  @override
  String memEntriesAndSize(String count, String size) {
    return '$count entries · $size';
  }

  @override
  String memOnDisk(String count, String size) {
    return 'on disk · $count entries · $size';
  }

  @override
  String memNoEntry(String size) {
    return '0 entries · $size';
  }

  @override
  String get searchSheetTitle => 'Search my playlists';

  @override
  String get searchSheetFieldLabel => 'Title to search';

  @override
  String searchSheetOriginalTitle(String title) {
    return 'Original title: $title';
  }

  @override
  String get searchSheetTooShort => 'Type at least 2 characters.';

  @override
  String get searchSheetNoResult => 'No title found in your playlists.';

  @override
  String nextEpPlayNow(int seconds) {
    return 'Play now  ·  ${seconds}s';
  }

  @override
  String get aboutDiagnosticLog => 'Diagnostic log';

  @override
  String get aboutSourceOnGithub => 'See the code on GitHub';

  @override
  String get aboutAllReleases => 'All releases';

  @override
  String get regionNoChange => 'No change';

  @override
  String get regionShowAll => 'Show all';

  @override
  String get regionHideAll => 'Hide all';

  @override
  String get visualLangTitle => 'Artwork language';

  @override
  String get visualLangAuto => 'Same as the device';

  @override
  String get visualLangOriginalLabel => 'Original version (no text)';

  @override
  String get visualLangSubFr => 'French posters and texts when they exist';

  @override
  String get visualLangSubEn => 'English posters and texts';

  @override
  String get visualLangSubOriginal =>
      'Poster without text when it exists, otherwise the original version';

  @override
  String visualLangCurrently(String tag) {
    return 'Currently: $tag';
  }

  @override
  String get qualityHideVersions => 'Hide the versions';

  @override
  String get qualityChangeVersion => 'Change version';

  @override
  String get navExitHint => '💡 To leave the app: press Back twice';

  @override
  String get navExitConfirm => 'Press Back again to leave';

  @override
  String get settingsUsageReset => '🧹 Usage data reset';

  @override
  String get errUnexpected => 'An unexpected error occurred.';

  @override
  String get errUnknown => 'An unknown error occurred.';

  @override
  String get relayNothingReadable =>
      'The conversion produced nothing playable.';

  @override
  String get healthNoStall => 'no stall';

  @override
  String get reloadLessThanMinute => 'less than a minute';

  @override
  String get plNoActiveAccount =>
      'No active account selected. Please choose one in the settings.';

  @override
  String get plNoActiveAccountShort => 'No active account selected.';

  @override
  String plInvalidUrl(String label) {
    return 'The playlist URL for the account “$label” is invalid. Check its configuration.';
  }

  @override
  String get plEmptyFile =>
      'The server returned an empty file. Check the playlist URL.';

  @override
  String get bkFileTooShort => 'Backup file too short or corrupted.';

  @override
  String get bkNotAnAetherFile => 'This is not a valid .aether file.';

  @override
  String get acctDefaultLabel => 'Default account';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get dlMediaStoreTimeout => 'MediaStore did not answer';

  @override
  String detRuntimePerEpisode(String minutes) {
    return '${minutes}m/episode';
  }

  @override
  String get detEpisodesBadSeriesId => 'unreadable series identifier';

  @override
  String get detEpisodesNoAccount => 'account not found';

  @override
  String memSourceAndParsed(String source, String parsed) {
    return 'source $source · parsed $parsed';
  }

  @override
  String expTodayOn(String date) {
    return 'Expires today ($date)';
  }

  @override
  String expTomorrowOn(String date) {
    return 'Expires tomorrow ($date)';
  }

  @override
  String get catFavorites => 'Favorites';

  @override
  String get catOthers => 'Other';

  @override
  String get catNew => 'New';

  @override
  String get catStaffPick => 'Staff picks';

  @override
  String get catSelection => 'Selection';

  @override
  String get catCult => 'Cult classics';

  @override
  String get catBoxOffice => 'Box office';

  @override
  String get catOscar => 'Oscars';

  @override
  String get catAction => 'Action';

  @override
  String get catNews => 'News';

  @override
  String get catAnimation => 'Animation';

  @override
  String get catMartialArts => 'Martial arts';

  @override
  String get catAdventure => 'Adventure';

  @override
  String get catBiopic => 'Biopic';

  @override
  String get catHeist => 'Heist';

  @override
  String get catDisaster => 'Disaster';

  @override
  String get catComedy => 'Comedy';

  @override
  String get catCrime => 'Crime';

  @override
  String get catDance => 'Dance';

  @override
  String get catDocumentary => 'Documentary';

  @override
  String get catDrama => 'Drama';

  @override
  String get catSpy => 'Spy';

  @override
  String get catFantasy => 'Fantasy';

  @override
  String get catHolidays => 'Holidays';

  @override
  String get catWar => 'War';

  @override
  String get catHistory => 'History';

  @override
  String get catHorror => 'Horror';

  @override
  String get catKids => 'Kids';

  @override
  String get catLegal => 'Legal';

  @override
  String get catKaraoke => 'Karaoke';

  @override
  String get catMafia => 'Mafia';

  @override
  String get catManga => 'Anime';

  @override
  String get catMaritime => 'Maritime';

  @override
  String get catMedical => 'Medical';

  @override
  String get catMedieval => 'Medieval';

  @override
  String get catMusical => 'Musical';

  @override
  String get catPolice => 'Crime drama';

  @override
  String get catPrison => 'Prison';

  @override
  String get catRomance => 'Romance';

  @override
  String get catSciFi => 'Sci-Fi';

  @override
  String get catStandUp => 'Stand-up';

  @override
  String get catSport => 'Sports';

  @override
  String get catSuperheroes => 'Superheroes';

  @override
  String get catSurvival => 'Survival';

  @override
  String get catTvMovie => 'TV movie';

  @override
  String get catRealityTv => 'Reality TV';

  @override
  String get catTalkShow => 'Talk shows';

  @override
  String get catThriller => 'Thriller';

  @override
  String get catSerialKiller => 'Serial killer';

  @override
  String get catRevenge => 'Revenge';

  @override
  String get catCars => 'Cars';

  @override
  String get catWestern => 'Western';

  @override
  String get regFrance => 'France';

  @override
  String get regAlbania => 'Albania';

  @override
  String get regAlgeria => 'Algeria';

  @override
  String get regGermany => 'Germany';

  @override
  String get regArmenia => 'Armenia';

  @override
  String get regAsia => 'Asia';

  @override
  String get regBelgium => 'Belgium';

  @override
  String get regBosnia => 'Bosnia';

  @override
  String get regBrazil => 'Brazil';

  @override
  String get regCanada => 'Canada';

  @override
  String get regCroatia => 'Croatia';

  @override
  String get regSpain => 'Spain';

  @override
  String get regGreece => 'Greece';

  @override
  String get regIndian => 'Indian';

  @override
  String get regItaly => 'Italy';

  @override
  String get regMaghreb => 'Maghreb';

  @override
  String get regNetherlands => 'Netherlands';

  @override
  String get regPoland => 'Poland';

  @override
  String get regPortugal => 'Portugal';

  @override
  String get regRamadan => 'Ramadan';

  @override
  String get regRomania => 'Romania';

  @override
  String get regRussia => 'Russia';

  @override
  String get regScandinavia => 'Scandinavia';

  @override
  String get regSwitzerland => 'Switzerland';

  @override
  String get regCzechia => 'Czechia';

  @override
  String get regExYugoslavia => 'Former Yugoslavia';

  @override
  String get regDominicanRepublic => 'Dominican Republic';

  @override
  String get regOriginalNonFrench => 'Original (non-French)';

  @override
  String get regLegendado => 'Legendado (PT subtitles)';

  @override
  String get acctChipMain => 'MAIN';

  @override
  String get bootEnterManually => 'Enter manually';

  @override
  String get bootConfigureWebConsole => 'Set up via Web console';

  @override
  String get searchPeople => 'People';

  @override
  String get personRoleDirector => 'Director';

  @override
  String get personRoleActor => 'Actor';

  @override
  String get personRoleWriter => 'Writer';

  @override
  String get personRoleProduction => 'Production';

  @override
  String get personRoleMusic => 'Music';

  @override
  String get personRoleCamera => 'Cinematography';

  @override
  String get optSpeedCurrentNormal => 'Normal (1.0×)';

  @override
  String get tracksTitle => 'Tracks';

  @override
  String get tracksSubtitle => 'audio & subtitles';

  @override
  String get tracksAudio => 'Audio';

  @override
  String get tracksSubtitles => 'Subtitles';

  @override
  String get epgNow => 'ON NOW';

  @override
  String get epgNext => 'NEXT';

  @override
  String get replayPrograms => 'Programmes';

  @override
  String get replayToday => 'Today';

  @override
  String get replayYesterday => 'Yesterday';

  @override
  String replayWatchLabel(String label) {
    return 'Watch  •  $label';
  }

  @override
  String qualityWatch(String label) {
    return 'Watch · $label';
  }

  @override
  String get actorBiography => 'Biography';

  @override
  String get actorBiographyMissing => 'No biography available.';

  @override
  String get actorAvailableBadge => 'AVAILABLE';

  @override
  String get detMainCast => 'Main cast';

  @override
  String get detSimilarAvailable => 'Similar titles available';

  @override
  String get detTrailerButton => 'TRAILER';

  @override
  String get themePreviewTitle => 'Movie Title';

  @override
  String get sheetReplay => 'Replay';

  @override
  String sheetReplayDays(int days) {
    return 'Replay (${days}d)';
  }

  @override
  String get memComputing => 'Calculating…';

  @override
  String get memRamProcess => 'Process RAM';

  @override
  String memRamProcessValue(String current, String peak) {
    return '$current (peak $peak)';
  }

  @override
  String get memImageCacheDisk => 'Image cache (disk)';

  @override
  String get memImageCacheRam => 'Image cache (RAM)';

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
  String sizeBytes(String n) {
    return '$n B';
  }

  @override
  String sizeKilobytes(String n) {
    return '$n kB';
  }

  @override
  String sizeMegabytes(String n) {
    return '$n MB';
  }

  @override
  String sizeGigabytes(String n) {
    return '$n GB';
  }

  @override
  String get dlActionRestart => 'Restart';

  @override
  String get dlMoreActions => 'More actions';

  @override
  String get playerQuit => 'Quit';

  @override
  String get nextEpContinue => 'Continue';

  @override
  String get commonClear => 'Clear';

  @override
  String get statsAnnouncedLabel => 'Declared';

  @override
  String get replayGuideUnavailable => 'Guide unavailable';

  @override
  String get replayNotAvailable => 'not available';

  @override
  String get detEnableTmdb => 'Turn on TMDB';

  @override
  String get dlRestartUpper => 'RESTART';

  @override
  String get commonDecrease => 'Decrease';

  @override
  String get commonIncrease => 'Increase';

  @override
  String get detEpisodesReasonNetwork => 'the server is not responding';

  @override
  String get detEpisodesReasonBusy =>
      'the provider refuses: too many connections at once';

  @override
  String get detEpisodesReasonParse => 'the server\'s answer could not be read';

  @override
  String get detEpisodesReasonAccount => 'the account settings are incomplete';

  @override
  String failDetailTooLong(String delay) {
    return '(still not ready after $delay)';
  }

  @override
  String get failDetailCacheCleared => '(cleared at your request)';

  @override
  String durationHoursMinutes(int hours, String minutes) {
    return '${hours}h ${minutes}m';
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
  String get healthNoStalls => 'no stalls';

  @override
  String healthStalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stalls',
      one: '$count stall',
    );
    return '$_temp0';
  }

  @override
  String healthPerHour(String value) {
    return '$value/h';
  }

  @override
  String healthWatched(String duration) {
    return '$duration watched';
  }

  @override
  String bootDetailEntries(int n, String count) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$count entries',
      one: '$count entry',
    );
    return '$_temp0';
  }

  @override
  String bootDetailSection(String section, String done, String total) {
    return '$section · $done/$total';
  }

  @override
  String get bootSectionLive => 'channels';

  @override
  String get bootSectionMovies => 'movies';

  @override
  String get bootSectionSeries => 'series';

  @override
  String get bootStepInit => '// starting…';

  @override
  String get bootStepServices => '// preparing services…';

  @override
  String get bootStepAccount => '// checking the account…';

  @override
  String get bootStepReadPlaylist => '// reading the playlist…';

  @override
  String get bootStepDownloadPlaylist => '// downloading the playlist…';

  @override
  String get bootStepAnalysis => '// parsing the catalog…';

  @override
  String get bootStepOtherAccounts => '// loading the other accounts…';

  @override
  String get bootStepReady => '// ready.';

  @override
  String bootStepUpdate(int index, int total, String label) {
    return '// updating $index/$total · $label…';
  }

  @override
  String bootStepAnalysisOf(String label) {
    return '// parsing · $label…';
  }

  @override
  String get playlistNoActiveAccount =>
      'No active account selected. Choose one in the settings.';

  @override
  String playlistInvalidUrl(String label) {
    return 'The playlist URL of the account “$label” is invalid. Check its settings.';
  }

  @override
  String detRuntimeHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get castOverlayLive => 'LIVE';

  @override
  String playerReconnectingNow(int attempt, int max) {
    return 'Reconnecting… ($attempt/$max)';
  }

  @override
  String get nextEpStayHere => 'Stay here';

  @override
  String get nowPlayingLive => 'Live';

  @override
  String get nowPlayingReplay => 'Replay';

  @override
  String tracksTrackN(String id) {
    return 'Track $id';
  }

  @override
  String replayManualTitle(String label) {
    return 'Replay — $label';
  }

  @override
  String get relayDolbyVisionP5 =>
      'This film is in Dolby Vision profile 5: without a Dolby Vision decoder, its colors would be wrong. It can\'t be converted for the TV.';

  @override
  String get dlNotifFinished => 'Download complete — tap to open';

  @override
  String get dlNotifFailed => 'Download failed';

  @override
  String get castNotifStop => 'Stop';

  @override
  String dlNoticeAverage(int percent) {
    return '$percent% on average';
  }

  @override
  String get termShow => '▼ SHOW';

  @override
  String get termHide => '▲ HIDE';

  @override
  String get updDiffLine => '> DIFF    : see the release on GitHub';

  @override
  String get updViewChangelog => '[ VIEW CHANGELOG ]';

  @override
  String get updLater => '[ LATER ]';

  @override
  String get updAbort => '[ ABORT ]';

  @override
  String get updInstall => '[ INSTALL UPDATE ]';

  @override
  String get updRetry => '[ RETRY ]';

  @override
  String get xmltvNoGuide => 'No guide saved';

  @override
  String get consoleCodeLabel => 'Code: ';

  @override
  String get consoleCopyUrl => 'Copy the address';

  @override
  String bkBackupFrom(String date, String version) {
    return 'Backup from $date (v$version):';
  }

  @override
  String qualityStreamN(int n) {
    return 'Stream $n';
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
    return 'Made with $stack';
  }

  @override
  String get acctCardActions => 'Account actions';

  @override
  String infoRowLabel(String label) {
    return '$label:';
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
  String get actorJobDirecting => 'Directing team';

  @override
  String get themePresetPhosphore => 'Phosphor';

  @override
  String get themePresetNordique => 'Nordic';

  @override
  String get themePresetMinimaliste => 'Minimalist';
}
