import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @downloadManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Manager'**
  String get downloadManagerTitle;

  /// No description provided for @noDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get noDownloads;

  /// No description provided for @downloadDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Start Download'**
  String get downloadDialogTitle;

  /// No description provided for @downloadDialogFileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get downloadDialogFileNameLabel;

  /// No description provided for @downloadDialogFileSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get downloadDialogFileSizeLabel;

  /// No description provided for @downloadDialogFileTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'File type'**
  String get downloadDialogFileTypeLabel;

  /// No description provided for @downloadDialogUnknownSize.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get downloadDialogUnknownSize;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @denied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. The download cannot begin.'**
  String get denied;

  /// No description provided for @terminalTitle.
  ///
  /// In en, this message translates to:
  /// **'//:FLUX_DOWNLOAD_INTERFACE'**
  String get terminalTitle;

  /// No description provided for @terminalResumeMessage.
  ///
  /// In en, this message translates to:
  /// **'🔄 Resuming download:\n🎞️ {fileName}'**
  String terminalResumeMessage(Object fileName);

  /// No description provided for @terminalStartMessage.
  ///
  /// In en, this message translates to:
  /// **'🤖 Starting download:\n🎞️ {fileName}'**
  String terminalStartMessage(Object fileName);

  /// No description provided for @terminalFileSizeMessage.
  ///
  /// In en, this message translates to:
  /// **'📦 File size: {fileSize}'**
  String terminalFileSizeMessage(Object fileSize);

  /// No description provided for @terminalFinalizingMessage.
  ///
  /// In en, this message translates to:
  /// **'\n⚙️ Finalizing...\nMoving file to public storage. Please wait.'**
  String get terminalFinalizingMessage;

  /// No description provided for @terminalSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'\n🟢 SUCCESS: Download complete!'**
  String get terminalSuccessMessage;

  /// No description provided for @terminalFatalErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'\n☣️ FATAL: An error occurred'**
  String get terminalFatalErrorMessage;

  /// No description provided for @terminalSpeedMessage.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get terminalSpeedMessage;

  /// No description provided for @terminalRetryCountMessage.
  ///
  /// In en, this message translates to:
  /// **'Retries'**
  String get terminalRetryCountMessage;

  /// No description provided for @terminalEtaMessage.
  ///
  /// In en, this message translates to:
  /// **'ETA'**
  String get terminalEtaMessage;

  /// No description provided for @terminalCancelMessage.
  ///
  /// In en, this message translates to:
  /// **'\nℹ️ ABORT: Download cancelled by user'**
  String get terminalCancelMessage;

  /// No description provided for @terminalCloseButton.
  ///
  /// In en, this message translates to:
  /// **'[ CLOSE ]'**
  String get terminalCloseButton;

  /// No description provided for @terminalAbortingButton.
  ///
  /// In en, this message translates to:
  /// **'[ PAUSE... ]'**
  String get terminalAbortingButton;

  /// No description provided for @terminalAbortButton.
  ///
  /// In en, this message translates to:
  /// **'[ PAUSE ]'**
  String get terminalAbortButton;

  /// No description provided for @searchPageDownloadsTooltip.
  ///
  /// In en, this message translates to:
  /// **'See downloads'**
  String get searchPageDownloadsTooltip;

  /// No description provided for @searchPageReloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reload playlist'**
  String get searchPageReloadTooltip;

  /// No description provided for @searchPageAccountsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Accounts and Settings'**
  String get searchPageAccountsTooltip;

  /// No description provided for @searchPageLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Could not load playlist'**
  String get searchPageLoadingError;

  /// No description provided for @searchPageRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get searchPageRetryButton;

  /// No description provided for @searchPageProcessingError.
  ///
  /// In en, this message translates to:
  /// **'Error processing playlist:'**
  String get searchPageProcessingError;

  /// No description provided for @searchFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchFieldHint;

  /// No description provided for @searchFilterFilms.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get searchFilterFilms;

  /// No description provided for @searchFilterSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get searchFilterSeries;

  /// No description provided for @searchFilterTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get searchFilterTv;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get searchNoResults;

  /// No description provided for @searchNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content to display.'**
  String get searchNoContent;

  /// No description provided for @actionSheetChooseVersion.
  ///
  /// In en, this message translates to:
  /// **'Choose a version for:'**
  String get actionSheetChooseVersion;

  /// No description provided for @chipSeasons.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 Season} other{{count} Seasons}}'**
  String chipSeasons(num count);

  /// No description provided for @chipEpisodes.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 Ep.} other{{count} Ep.}}'**
  String chipEpisodes(num count);

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @favoriteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favoriteAdd;

  /// No description provided for @favoriteRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get favoriteRemove;

  /// No description provided for @actionSheetPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionSheetPlay;

  /// No description provided for @actionSheetPlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Starts playback (automatic caching).'**
  String get actionSheetPlaySubtitle;

  /// No description provided for @actionSheetDownload.
  ///
  /// In en, this message translates to:
  /// **'Download in background'**
  String get actionSheetDownload;

  /// No description provided for @actionSheetDownloadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'To watch later without a connection.'**
  String get actionSheetDownloadSubtitle;

  /// No description provided for @deleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete file?'**
  String get deleteDialogTitle;

  /// No description provided for @deleteDialogSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get deleteDialogSizeLabel;

  /// No description provided for @deleteDialogWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible and the file will be permanently deleted.'**
  String get deleteDialogWarning;

  /// No description provided for @deleteDialogConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteDialogConfirmButton;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deleteTooltip;

  /// No description provided for @taskStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get taskStatusDownloading;

  /// No description provided for @taskStatusRemaining.
  ///
  /// In en, this message translates to:
  /// **' • {remainingSize} left'**
  String taskStatusRemaining(Object remainingSize);

  /// No description provided for @taskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed • {size} • {date}'**
  String taskStatusCompleted(Object date, Object size);

  /// No description provided for @taskStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed {progressInfo} • Tap to retry'**
  String taskStatusFailed(Object progressInfo);

  /// No description provided for @taskStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled {progressInfo} • Tap to retry'**
  String taskStatusCanceled(Object progressInfo);

  /// No description provided for @taskStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending • {date}'**
  String taskStatusPending(Object date);

  /// No description provided for @taskStatusUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get taskStatusUnknownError;

  /// No description provided for @playlistCardSubtitleNone.
  ///
  /// In en, this message translates to:
  /// **'No playlist downloaded in this context.'**
  String get playlistCardSubtitleNone;

  /// No description provided for @playlistCardSubtitleLastFile.
  ///
  /// In en, this message translates to:
  /// **'Last file: {path}'**
  String playlistCardSubtitleLastFile(Object path);

  /// No description provided for @playlistDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download / Update'**
  String get playlistDownloadButton;

  /// No description provided for @playlistDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get playlistDeleteButton;

  /// No description provided for @playlistManagementTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: You can also reload the playlist from the settings gear or via the refresh icon on the search screen.'**
  String get playlistManagementTip;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get accountsTitle;

  /// No description provided for @deleteAccountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountDialogTitle;

  /// No description provided for @deleteAccountDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent.'**
  String get deleteAccountDialogContent;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirm;

  /// No description provided for @playlistInfoChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking playlist...'**
  String get playlistInfoChecking;

  /// No description provided for @playlistInfoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No playlist available or loading error.'**
  String get playlistInfoUnavailable;

  /// No description provided for @playlistInfoTryReload.
  ///
  /// In en, this message translates to:
  /// **'Try reloading'**
  String get playlistInfoTryReload;

  /// No description provided for @playlistInfoLocalFile.
  ///
  /// In en, this message translates to:
  /// **'Local playlist file'**
  String get playlistInfoLocalFile;

  /// No description provided for @playlistInfoSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get playlistInfoSize;

  /// No description provided for @playlistInfoLastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Upd.'**
  String get playlistInfoLastUpdate;

  /// No description provided for @playlistInfoEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get playlistInfoEntries;

  /// No description provided for @playlistInfoReloadButton.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get playlistInfoReloadButton;

  /// No description provided for @playlistInfoDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get playlistInfoDeleteButton;

  /// No description provided for @accountsListEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsListEmpty;

  /// No description provided for @accountModeComplete.
  ///
  /// In en, this message translates to:
  /// **'Mode: Full URL — {host}'**
  String accountModeComplete(Object host);

  /// No description provided for @accountModeSeparate.
  ///
  /// In en, this message translates to:
  /// **'Mode: Separate — {username}@{host}'**
  String accountModeSeparate(Object host, Object username);

  /// No description provided for @accountActionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get accountActionEdit;

  /// No description provided for @accountActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get accountActionDelete;

  /// No description provided for @accountsFab.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get accountsFab;

  /// No description provided for @editAccountTitleAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get editAccountTitleAdd;

  /// No description provided for @editAccountTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Account'**
  String get editAccountTitleEdit;

  /// No description provided for @editAccountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Account name (e.g., Living Room, Vacation...)'**
  String get editAccountNameLabel;

  /// No description provided for @editAccountNameHint.
  ///
  /// In en, this message translates to:
  /// **'My IPTV Account'**
  String get editAccountNameHint;

  /// No description provided for @editAccountNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get editAccountNameRequired;

  /// No description provided for @editAccountModeUrl.
  ///
  /// In en, this message translates to:
  /// **'Full URL'**
  String get editAccountModeUrl;

  /// No description provided for @editAccountModeCredentials.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get editAccountModeCredentials;

  /// No description provided for @editAccountFullUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Full .m3u URL'**
  String get editAccountFullUrlLabel;

  /// No description provided for @editAccountFullUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL'**
  String get editAccountFullUrlInvalid;

  /// No description provided for @editAccountServerUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server URL (e.g., http://host:port)'**
  String get editAccountServerUrlLabel;

  /// No description provided for @editAccountUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get editAccountUsernameLabel;

  /// No description provided for @editAccountPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get editAccountPasswordLabel;

  /// No description provided for @editAccountPlaylistTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Playlist type'**
  String get editAccountPlaylistTypeLabel;

  /// No description provided for @editAccountPlaylistTypeM3u.
  ///
  /// In en, this message translates to:
  /// **'M3U (Standard)'**
  String get editAccountPlaylistTypeM3u;

  /// No description provided for @editAccountPlaylistTypeSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple (Single link)'**
  String get editAccountPlaylistTypeSimple;

  /// No description provided for @editAccountCookiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Cookies (optional)'**
  String get editAccountCookiesLabel;

  /// No description provided for @editAccountCookiesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., PHPSESSID=xxxxxx;'**
  String get editAccountCookiesHint;

  /// No description provided for @editAccountSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editAccountSaveButton;

  /// No description provided for @playerGenericError.
  ///
  /// In en, this message translates to:
  /// **'Unable to play this media.'**
  String get playerGenericError;

  /// No description provided for @playerLoading.
  ///
  /// In en, this message translates to:
  /// **'Initializing player...'**
  String get playerLoading;

  /// No description provided for @playerLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Loading error: {error}'**
  String playerLoadingError(Object error);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupTitle;

  /// No description provided for @optimizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Optimization'**
  String get optimizationTitle;

  /// No description provided for @regionFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Languages / regions'**
  String get regionFilterTitle;

  /// No description provided for @themeSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeSettingsTitle;

  /// No description provided for @tmdbKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'TMDB API key'**
  String get tmdbKeyTitle;

  /// No description provided for @xmltvTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel guide'**
  String get xmltvTitle;

  /// No description provided for @webConsoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Web console'**
  String get webConsoleTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloads;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Control from your phone'**
  String get settingsSectionPhone;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Web console'**
  String get settingsWebConsole;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Accounts, backup, theme, EPG, TMDB + remote (QR)'**
  String get settingsWebConsoleSub;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Sources & accounts'**
  String get settingsSectionSources;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'IPTV accounts'**
  String get settingsAccounts;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Providers, playlist stats & reload'**
  String get settingsAccountsSub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'TMDB API key'**
  String get settingsTmdbKey;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Posters, overviews, cast (optional)'**
  String get settingsTmdbKeySub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Channel guide'**
  String get settingsXmltv;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'XMLTV EPG — French DTT'**
  String get settingsXmltvSub;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsSectionDisplay;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Languages / regions'**
  String get settingsRegions;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Hide foreign content (saves memory)'**
  String get settingsRegionsSub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Theme, colours, cyberpunk effects'**
  String get settingsThemeSub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsOptimization;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Performance profiles, hero, thumbnails, memory'**
  String get settingsOptimizationSub;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Backup & app'**
  String get settingsSectionBackup;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Backup / Restore'**
  String get settingsBackup;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Export/import accounts, TMDB, theme, favourites (encrypted .aether)'**
  String get settingsBackupSub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Version + update check'**
  String get settingsAboutSub;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Reset usage data'**
  String get settingsResetUsage;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Clears favourites, resume points & history (keeps accounts & theme)'**
  String get settingsResetUsageSub;

  /// Reset confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Reset usage data?'**
  String get settingsResetTitle;

  /// Reset confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'Clears favourites, resume points (movies & series), search history and the last watched channel.\n\nKeeps IPTV accounts, the TMDB key, the theme and the language/region filters.\n\nThis cannot be undone.'**
  String get settingsResetBody;

  /// Reset confirmation button
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetConfirm;

  /// Generic cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Network error shown to the user
  ///
  /// In en, this message translates to:
  /// **'Cannot connect: no network, or the server is unreachable.'**
  String get errNetworkUnreachable;

  /// Timeout error
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer.'**
  String get errTimeout;

  /// Timeout error with hint
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer. Check your connection or the server address.'**
  String get errTimeoutHint;

  /// TLS error
  ///
  /// In en, this message translates to:
  /// **'Secure connection refused by the server (certificate).'**
  String get errTls;

  /// Malformed response error
  ///
  /// In en, this message translates to:
  /// **'Unreadable answer from the server (unexpected format).'**
  String get errBadFormat;

  /// File system error
  ///
  /// In en, this message translates to:
  /// **'Cannot read or write the file on this device.'**
  String get errFileSystem;

  /// Internal error
  ///
  /// In en, this message translates to:
  /// **'Something went wrong inside the app.'**
  String get errInternal;

  /// Invalid response error
  ///
  /// In en, this message translates to:
  /// **'Invalid answer from the server. Check the address.'**
  String get errBadResponse;

  /// 401/403 error
  ///
  /// In en, this message translates to:
  /// **'Access denied by the server (HTTP {code}). Check the account credentials.'**
  String errForbidden(int code);

  /// 404 error
  ///
  /// In en, this message translates to:
  /// **'Address not found on the server (HTTP 404).'**
  String get errNotFound;

  /// 5xx error
  ///
  /// In en, this message translates to:
  /// **'The server is failing (HTTP {code}). Try again later.'**
  String errServer(int code);

  /// Generic HTTP error
  ///
  /// In en, this message translates to:
  /// **'The server answered with an error (HTTP {code}).'**
  String errHttp(int code);

  /// Connection error
  ///
  /// In en, this message translates to:
  /// **'Connection error: check that you are online and that the server is reachable.'**
  String get errConnection;

  /// Cancelled operation
  ///
  /// In en, this message translates to:
  /// **'Operation cancelled.'**
  String get errCancelled;

  /// Unknown network error
  ///
  /// In en, this message translates to:
  /// **'Unknown network error.'**
  String get errNetworkUnknown;

  /// Home row: TMDB recommendations seeded by the last watched title
  ///
  /// In en, this message translates to:
  /// **'Because you watched “{title}”'**
  String rowBecauseYouWatched(String title);

  /// Home row: TMDB top rated titles available in the lists
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get rowTopRated;

  /// TMDB option title
  ///
  /// In en, this message translates to:
  /// **'“Because you watched” row'**
  String get tmdbRowsBecauseTitle;

  /// TMDB option subtitle
  ///
  /// In en, this message translates to:
  /// **'Titles close to what you last watched, picked from your lists'**
  String get tmdbRowsBecauseSub;

  /// TMDB option title
  ///
  /// In en, this message translates to:
  /// **'“Top rated” row'**
  String get tmdbRowsTopRatedTitle;

  /// TMDB option subtitle
  ///
  /// In en, this message translates to:
  /// **'The best-rated titles your lists offer'**
  String get tmdbRowsTopRatedSub;

  /// Optimisation setting title
  ///
  /// In en, this message translates to:
  /// **'Rows: minimum titles'**
  String get perfMinItemsTitle;

  /// Optimisation setting subtitle
  ///
  /// In en, this message translates to:
  /// **'Below this, the row folds into “Others” — never New or Favourites. 1 = never fold.'**
  String get perfMinItemsSub;

  /// Downloads: section of files found on device but absent from the list
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get dlOnDeviceTitle;

  /// Downloads: section subtitle
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) · {size} — in Movies/AetherStream, missing from the list'**
  String dlOnDeviceSub(int count, String size);

  /// Downloads: scan button tooltip
  ///
  /// In en, this message translates to:
  /// **'Look for files on this device'**
  String get dlScanTooltip;

  /// Downloads: scan result
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) on device, missing from the list ({size})'**
  String dlScanFound(int count, String size);

  /// Downloads: scan found nothing
  ///
  /// In en, this message translates to:
  /// **'Nothing new on this device'**
  String get dlScanNothing;

  /// Downloads: permission denied
  ///
  /// In en, this message translates to:
  /// **'Without video access, the folder cannot be read'**
  String get dlScanDenied;

  /// Delete confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete this file?'**
  String get dlOrphanDeleteTitle;

  /// Delete confirmation body
  ///
  /// In en, this message translates to:
  /// **'“{name}” ({size}) will be erased from this device. This cannot be undone.'**
  String dlOrphanDeleteBody(String name, String size);

  /// Delete done
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get dlOrphanDeleted;

  /// Delete refused
  ///
  /// In en, this message translates to:
  /// **'Android refused the deletion'**
  String get dlOrphanDeleteFailed;

  /// Play action
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get dlOrphanPlay;

  /// Generic delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Status banner, key present
  ///
  /// In en, this message translates to:
  /// **'TMDB connected: posters, overviews and cast'**
  String get tmdbStatusOn;

  /// Status banner, no key
  ///
  /// In en, this message translates to:
  /// **'No TMDB key: no extra posters or overviews. The app still works.'**
  String get tmdbStatusOff;

  /// TV pairing card title, key present
  ///
  /// In en, this message translates to:
  /// **'Replace from my phone'**
  String get tmdbPairReplace;

  /// TV pairing card title, no key
  ///
  /// In en, this message translates to:
  /// **'Set up from my phone'**
  String get tmdbPairSetup;

  /// TV pairing card subtitle
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code and paste the key from your phone'**
  String get tmdbPairSub;

  /// Key field section title
  ///
  /// In en, this message translates to:
  /// **'TMDB key'**
  String get tmdbKeySection;

  /// Key field section title on TV, manual entry
  ///
  /// In en, this message translates to:
  /// **'Typing with the remote'**
  String get tmdbKeySectionManual;

  /// Key field hint
  ///
  /// In en, this message translates to:
  /// **'Paste your key here…'**
  String get tmdbKeyHint;

  /// Reveal key tooltip
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get tmdbKeyShow;

  /// Hide key tooltip
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get tmdbKeyHide;

  /// Save key button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get tmdbKeySave;

  /// Delete key button
  ///
  /// In en, this message translates to:
  /// **'Remove the key'**
  String get tmdbKeyRemove;

  /// TV: reveal the manual field
  ///
  /// In en, this message translates to:
  /// **'Type it with the remote'**
  String get tmdbKeyManualEntry;

  /// Snackbar after a valid key
  ///
  /// In en, this message translates to:
  /// **'TMDB connected'**
  String get tmdbKeyConnected;

  /// Snackbar after deleting the key
  ///
  /// In en, this message translates to:
  /// **'TMDB key removed'**
  String get tmdbKeyRemoved;

  /// Snackbar when TMDB answers 401
  ///
  /// In en, this message translates to:
  /// **'TMDB rejected this key. Make sure you copied the API Read Access Token.'**
  String get tmdbKeyRejected;

  /// Snackbar when the probe could not run
  ///
  /// In en, this message translates to:
  /// **'Key saved. It could not be checked right now (no network).'**
  String get tmdbKeyUnverified;

  /// Save button label while probing
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get tmdbKeyChecking;

  /// How-to block title
  ///
  /// In en, this message translates to:
  /// **'Get a key (free)'**
  String get tmdbHowTitle;

  /// How-to step 1
  ///
  /// In en, this message translates to:
  /// **'Create an account on themoviedb.org'**
  String get tmdbHowStep1;

  /// How-to step 2
  ///
  /// In en, this message translates to:
  /// **'Open Settings, then API'**
  String get tmdbHowStep2;

  /// How-to step 3
  ///
  /// In en, this message translates to:
  /// **'Copy the API Read Access Token'**
  String get tmdbHowStep3;

  /// How-to step 4
  ///
  /// In en, this message translates to:
  /// **'Paste it below'**
  String get tmdbHowStep4;

  /// Signup button
  ///
  /// In en, this message translates to:
  /// **'Create a TMDB account'**
  String get tmdbSignup;

  /// Login link
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get tmdbLogin;

  /// Options section title
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get tmdbOptionsTitle;

  /// Visual language tile title
  ///
  /// In en, this message translates to:
  /// **'Language of visuals'**
  String get tmdbVisualLangTitle;

  /// Visual language tile subtitle
  ///
  /// In en, this message translates to:
  /// **'{lang}: posters, overviews and cast'**
  String tmdbVisualLangSub(String lang);

  /// Posters-first switch title
  ///
  /// In en, this message translates to:
  /// **'TMDB posters first'**
  String get tmdbPostersFirstTitle;

  /// Posters-first switch subtitle, on
  ///
  /// In en, this message translates to:
  /// **'In the carousel and favourites, the TMDB poster replaces the list\'s'**
  String get tmdbPostersFirstOn;

  /// Posters-first switch subtitle, off
  ///
  /// In en, this message translates to:
  /// **'Posters come from your lists; TMDB fills in the missing ones'**
  String get tmdbPostersFirstOff;

  /// Maintenance section title
  ///
  /// In en, this message translates to:
  /// **'Stored data'**
  String get tmdbMemoryTitle;

  /// Poster cache tile title
  ///
  /// In en, this message translates to:
  /// **'Posters'**
  String get tmdbMemoryPosters;

  /// Poster cache empty
  ///
  /// In en, this message translates to:
  /// **'No poster stored yet'**
  String get tmdbMemoryPostersNone;

  /// Poster cache count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 poster stored} other{{count} posters stored}}'**
  String tmdbMemoryPostersCount(int count);

  /// Clear cache button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get tmdbMemoryClear;

  /// Snackbar after clearing posters
  ///
  /// In en, this message translates to:
  /// **'Posters cleared. They will reload as you browse.'**
  String get tmdbMemoryPostersCleared;

  /// Inferred categories tile title
  ///
  /// In en, this message translates to:
  /// **'Automatic sorting'**
  String get tmdbMemorySorting;

  /// Inferred categories empty
  ///
  /// In en, this message translates to:
  /// **'Nothing to relearn: your lists already sort their titles'**
  String get tmdbMemorySortingNone;

  /// Inferred categories count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 title sorted thanks to TMDB} other{{count} titles sorted thanks to TMDB}}'**
  String tmdbMemorySortingCount(int count);

  /// Relearn button
  ///
  /// In en, this message translates to:
  /// **'Relearn'**
  String get tmdbMemoryRelearn;

  /// Snackbar after clearing inferred categories
  ///
  /// In en, this message translates to:
  /// **'Sorting cleared. It will rebuild as you browse the home.'**
  String get tmdbMemorySortingCleared;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
