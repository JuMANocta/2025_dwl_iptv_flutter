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
    Locale('fr'),
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

  /// No description provided for @terminalEtaMessage.
  ///
  /// In en, this message translates to:
  /// **'ETA'**
  String get terminalEtaMessage;

  /// No description provided for @terminalElapsedMessage.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get terminalElapsedMessage;

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

  /// No description provided for @actionSheetDownload.
  ///
  /// In en, this message translates to:
  /// **'Download in background'**
  String get actionSheetDownload;

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

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirm;

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

  /// No description provided for @editAccountSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editAccountSaveButton;

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
  /// **'TMDB posters & info'**
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
  /// **'TMDB posters & info'**
  String get settingsTmdbKey;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Posters, overviews, cast — optional'**
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

  /// Confirmation title before deleting the TMDB key
  ///
  /// In en, this message translates to:
  /// **'Remove the TMDB key?'**
  String get tmdbKeyRemoveTitle;

  /// Confirmation body before deleting the TMDB key
  ///
  /// In en, this message translates to:
  /// **'Posters and info from TMDB will no longer load until a key is entered again.'**
  String get tmdbKeyRemoveQuestion;

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
  /// **'Carousel and favourites use the TMDB poster.'**
  String get tmdbPostersFirstOn;

  /// Posters-first switch subtitle, off
  ///
  /// In en, this message translates to:
  /// **'Carousel and favourites keep your lists\' poster.'**
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

  /// Title of the confirmation dialog before reloading every list
  ///
  /// In en, this message translates to:
  /// **'Reload all lists?'**
  String get reloadAllTitle;

  /// Body of the reload-all confirmation, nothing is recent
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The list will be downloaded again from its server. This can take several minutes.} other{All {count} lists will be downloaded again from their servers. This can take several minutes.}}'**
  String reloadAllBody(int count);

  /// Body of the reload-all confirmation, naming the lists downloaded recently
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The list will be downloaded again from its server.}other{All {count} lists will be downloaded again from their servers.}}\n\nAlready up to date (less than 24 h): {names}.\n\nThis can take several minutes.'**
  String reloadAllBodyRecent(int count, String names);

  /// Confirm button of the reload-all dialog
  ///
  /// In en, this message translates to:
  /// **'Reload all'**
  String get reloadAllConfirm;

  /// Title of the progress dialog while every list is reloaded
  ///
  /// In en, this message translates to:
  /// **'Reloading'**
  String get reloadAllProgressTitle;

  /// Dismisses the reload progress dialog while the batch keeps running.
  ///
  /// In en, this message translates to:
  /// **'Continue in the background'**
  String get reloadAllBackground;

  /// First line of the progress dialog, before the first list starts
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get reloadAllPreparing;

  /// Progress line naming the list being reloaded
  ///
  /// In en, this message translates to:
  /// **'List {index}/{total} — {label}'**
  String reloadAllStep(int index, int total, String label);

  /// Tooltip of the reload button in the home app bar
  ///
  /// In en, this message translates to:
  /// **'Reload all lists'**
  String get reloadAllTooltip;

  /// Snackbar when the reload button is pressed without any account
  ///
  /// In en, this message translates to:
  /// **'No list to reload'**
  String get reloadAllNoAccounts;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get infoSectionTitle;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get infoGenre;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get infoDirector;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get infoCreator;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Original title'**
  String get infoOriginalTitle;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get infoCountry;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Studios'**
  String get infoStudios;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get infoStatus;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get infoRuntime;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get infoEpisodeLength;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get infoSeasons;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get infoNextEpisode;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get infoNetwork;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get infoBudget;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Box office'**
  String get infoRevenue;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Theatrical release'**
  String get infoTheatrical;

  /// Libelle de l'encadre Infos de la fiche
  ///
  /// In en, this message translates to:
  /// **'Digital release'**
  String get infoDigital;

  /// Saisons et episodes annonces par TMDB
  ///
  /// In en, this message translates to:
  /// **'{seasons} ({episodes, plural, =1{1 episode} other{{episodes} episodes}})'**
  String infoSeasonsValue(int seasons, int episodes);

  /// Sous-titre de la tuile Tout recharger (TV)
  ///
  /// In en, this message translates to:
  /// **'Re-download all your lists from their servers'**
  String get settingsReloadAllSub;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get perfProfileConfort;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get perfProfileEquilibre;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get perfProfilePerformance;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get autoProfileOk;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'What your device can do'**
  String get capsTitle;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Decoders, display, memory — measured, not guessed'**
  String get capsSub;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Measure again'**
  String get capsMeasure;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Not measured yet'**
  String get capsNever;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get capsDisplay;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get capsMemory;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Video decoders'**
  String get capsDecoders;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'4K films'**
  String get capsVerdict4k;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'hardware'**
  String get capsHardware;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'software'**
  String get capsSoftware;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'no decoder'**
  String get capsNoDecoder;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get capsYes;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'No — no decoder accepts 2160p'**
  String get capsNoDecoder4k;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'No — the display shows less than 2160p'**
  String get capsNoDisplay4k;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Unknown — incomplete measurement'**
  String get capsUnknown;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'low-memory device'**
  String get capsLowRam;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'This 4K version can\'t play here'**
  String get refuse4kTitle;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'No decoder on this device accepts a 3840×2160 picture. Pick an FHD or HD version.'**
  String get refuse4kDecoder;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'The display shows {w}×{h}: 4K would be decoded for nothing and may stutter. Pick an FHD or HD version.'**
  String refuse4kDisplay(int w, int h);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get refuseOk;

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'{name} profile chosen for this device'**
  String autoProfileTitle(String name);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Based on the measurement ({ram} MB of memory, {cores} cores), the home uses the {name} profile. You can change it anytime in Settings → Optimisation.'**
  String autoProfileBody(String name, int ram, int cores);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'Measured on {date}'**
  String capsMeasuredAt(String date);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'{w}×{h} at {hz} Hz'**
  String capsDisplayValue(int w, int h, int hz);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'{total} MB total, {avail} MB free'**
  String capsMemoryValue(int total, int avail);

  /// §deviceCaps
  ///
  /// In en, this message translates to:
  /// **'{name} ({kind}) — up to {w}×{h}'**
  String capsDecoderValue(String name, String kind, int w, int h);

  /// Sous-titre d'un profil d'optimisation
  ///
  /// In en, this message translates to:
  /// **'All animations'**
  String get perfProfileConfortSub;

  /// Sous-titre d'un profil d'optimisation
  ///
  /// In en, this message translates to:
  /// **'Static hero, shorter rows'**
  String get perfProfileEquilibreSub;

  /// Sous-titre d'un profil d'optimisation
  ///
  /// In en, this message translates to:
  /// **'Low memory'**
  String get perfProfilePerformanceSub;

  /// §tmdbProviders
  ///
  /// In en, this message translates to:
  /// **'Netflix, Disney+ and Prime trends'**
  String get tmdbRowsProvidersTitle;

  /// §tmdbProviders
  ///
  /// In en, this message translates to:
  /// **'What\'s popular right now on each platform in France, from your lists'**
  String get tmdbRowsProvidersSub;

  /// §tmdbProviders
  ///
  /// In en, this message translates to:
  /// **'Trending on {name}'**
  String rowProviderTrending(String name);

  /// No description provided for @perfDownloadsSection.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get perfDownloadsSection;

  /// No description provided for @perfParallelDownloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Simultaneous transfers'**
  String get perfParallelDownloadsTitle;

  /// No description provided for @perfParallelDownloadsSub.
  ///
  /// In en, this message translates to:
  /// **'One transfer at a time per subscription: providers accept a single connection, and the player keeps one. This number only applies across different subscriptions; the others wait their turn.'**
  String get perfParallelDownloadsSub;

  /// No description provided for @taskStatusQueuedWhy.
  ///
  /// In en, this message translates to:
  /// **'Waiting: one transfer at a time per subscription'**
  String get taskStatusQueuedWhy;

  /// No description provided for @perfWifiOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Download on Wi-Fi only'**
  String get perfWifiOnlyTitle;

  /// No description provided for @perfWifiOnlySub.
  ///
  /// In en, this message translates to:
  /// **'On mobile data (or a metered hotspot), transfers wait and resume on their own as soon as Wi-Fi or a wired connection is back.'**
  String get perfWifiOnlySub;

  /// No description provided for @taskStatusWaitWifi.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi (metered network)'**
  String get taskStatusWaitWifi;

  /// No description provided for @taskStatusWaitNetwork.
  ///
  /// In en, this message translates to:
  /// **'Waiting for network'**
  String get taskStatusWaitNetwork;

  /// No description provided for @offlineBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline — only downloaded files can be played'**
  String get offlineBannerTitle;

  /// No description provided for @offlineBannerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get offlineBannerRetry;

  /// No description provided for @offlineBootMessage.
  ///
  /// In en, this message translates to:
  /// **'No network to load your lists. Your downloaded files are still here; the app will resume on its own as soon as the connection is back.'**
  String get offlineBootMessage;

  /// No description provided for @capsDisplayModesNote.
  ///
  /// In en, this message translates to:
  /// **'The screen reports up to {w}×{h}. Android renders the UI smaller; video plays at native size.'**
  String capsDisplayModesNote(int w, int h);

  /// No description provided for @capsDisplayUiNote.
  ///
  /// In en, this message translates to:
  /// **'What Android reports here describes the UI, not necessarily the panel: many 4K TVs render menus at 1080p and video at 2160p. Only the decoders decide about 4K.'**
  String get capsDisplayUiNote;

  /// No description provided for @perfPurgeNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to reclaim — no orphan files'**
  String get perfPurgeNothing;

  /// No description provided for @perfPurgeDone.
  ///
  /// In en, this message translates to:
  /// **'🧹 {size} freed ({count} file(s))'**
  String perfPurgeDone(String size, int count);

  /// No description provided for @perfResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset settings?'**
  String get perfResetTitle;

  /// No description provided for @perfResetQuestion.
  ///
  /// In en, this message translates to:
  /// **'All optimization settings return to their default values.'**
  String get perfResetQuestion;

  /// No description provided for @perfResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get perfResetConfirm;

  /// No description provided for @perfResetDone.
  ///
  /// In en, this message translates to:
  /// **'Settings reset'**
  String get perfResetDone;

  /// No description provided for @perfFreeMemoryDone.
  ///
  /// In en, this message translates to:
  /// **'💤 {count} secondary account(s) unloaded from memory'**
  String perfFreeMemoryDone(int count);

  /// No description provided for @perfFreeMemoryNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to free (only one account loaded)'**
  String get perfFreeMemoryNothing;

  /// No description provided for @perfImageCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'🧹 Image cache cleared'**
  String get perfImageCacheCleared;

  /// No description provided for @perfSectionProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get perfSectionProfiles;

  /// No description provided for @perfSectionHero.
  ///
  /// In en, this message translates to:
  /// **'Hero banner'**
  String get perfSectionHero;

  /// No description provided for @perfHeroSub.
  ///
  /// In en, this message translates to:
  /// **'Stack of cards at the top of the home screen (costly on low-end boxes)'**
  String get perfHeroSub;

  /// No description provided for @perfAutoRotateTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic rotation'**
  String get perfAutoRotateTitle;

  /// No description provided for @perfAutoRotateSub.
  ///
  /// In en, this message translates to:
  /// **'Rotates the hero every 6 s (manual swipe still works)'**
  String get perfAutoRotateSub;

  /// No description provided for @perfHeroCardsLabel.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get perfHeroCardsLabel;

  /// No description provided for @perfSectionRows.
  ///
  /// In en, this message translates to:
  /// **'Category rows'**
  String get perfSectionRows;

  /// No description provided for @perfItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get perfItemsLabel;

  /// No description provided for @perfItemsSub.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails shown per row before the “See all” tile (Favorites are never truncated).'**
  String get perfItemsSub;

  /// No description provided for @perfSectionPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get perfSectionPlayback;

  /// No description provided for @perfAutoNextTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic next episode'**
  String get perfAutoNextTitle;

  /// No description provided for @perfAutoNextSub.
  ///
  /// In en, this message translates to:
  /// **'Plays the next episode at the end, after a countdown you can cancel. A season change always asks for confirmation.'**
  String get perfAutoNextSub;

  /// No description provided for @perfBufferLabel.
  ///
  /// In en, this message translates to:
  /// **'Playback buffer'**
  String get perfBufferLabel;

  /// No description provided for @perfBufferSub.
  ///
  /// In en, this message translates to:
  /// **'Seconds of video kept ahead. Raising it helps with a throttling provider — playback draws from the buffer instead of stalling — but holds that much more stream in memory, which matters on a set-top box. The “Stalls” counter in the Video info panel tells you whether the setting helps. Takes effect on the next playback.'**
  String get perfBufferSub;

  /// No description provided for @perfSectionLists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get perfSectionLists;

  /// No description provided for @perfKeepListsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep every playlist in memory'**
  String get perfKeepListsTitle;

  /// No description provided for @perfKeepListsSub.
  ///
  /// In en, this message translates to:
  /// **'Every account stays loaded: cross-account search and instant playlist switching. Costs memory (~50 to 150 MB per playlist) — turn it off on a Fire Stick or a low-RAM box.'**
  String get perfKeepListsSub;

  /// No description provided for @perfUnloadAfterLabel.
  ///
  /// In en, this message translates to:
  /// **'Unload after'**
  String get perfUnloadAfterLabel;

  /// No description provided for @perfUnloadNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get perfUnloadNever;

  /// No description provided for @perfMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String perfMinutesShort(int count);

  /// No description provided for @perfUnloadSub.
  ///
  /// In en, this message translates to:
  /// **'Minutes without opening a secondary playlist before it leaves memory. “Never” (0) is the same as keeping every playlist.'**
  String get perfUnloadSub;

  /// No description provided for @perfSectionMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory & usage'**
  String get perfSectionMemory;

  /// No description provided for @perfImageRamLabel.
  ///
  /// In en, this message translates to:
  /// **'Images (RAM)'**
  String get perfImageRamLabel;

  /// No description provided for @perfImageRamSub.
  ///
  /// In en, this message translates to:
  /// **'RAM reserved for images already displayed. Only adjust it if memory is genuinely short.'**
  String get perfImageRamSub;

  /// No description provided for @perfFreeMemoryButton.
  ///
  /// In en, this message translates to:
  /// **'Free memory from secondary accounts'**
  String get perfFreeMemoryButton;

  /// No description provided for @perfClearImageCacheButton.
  ///
  /// In en, this message translates to:
  /// **'Clear the image cache'**
  String get perfClearImageCacheButton;

  /// No description provided for @perfClearImageCacheNote.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails are kept on disk to avoid downloading them again. Clear it if a poster changed on the provider side or if storage is running out.'**
  String get perfClearImageCacheNote;

  /// No description provided for @perfSectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get perfSectionStorage;

  /// No description provided for @perfStorageScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning storage…'**
  String get perfStorageScanning;

  /// No description provided for @perfStorageNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to reclaim: every file belongs to an existing account.'**
  String get perfStorageNothing;

  /// No description provided for @perfStorageReclaimable.
  ///
  /// In en, this message translates to:
  /// **'{size} taken by {count} file(s) nothing needs any more: lists from deleted accounts, and interrupted downloads that can no longer resume.'**
  String perfStorageReclaimable(String size, int count);

  /// No description provided for @perfPurging.
  ///
  /// In en, this message translates to:
  /// **'Cleaning…'**
  String get perfPurging;

  /// No description provided for @perfPurgeButton.
  ///
  /// In en, this message translates to:
  /// **'Clean up orphan files'**
  String get perfPurgeButton;

  /// No description provided for @perfUnitSeconds.
  ///
  /// In en, this message translates to:
  /// **' s'**
  String get perfUnitSeconds;

  /// No description provided for @perfUnitMegabytes.
  ///
  /// In en, this message translates to:
  /// **' MB'**
  String get perfUnitMegabytes;

  /// No description provided for @acctAddHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to add a playlist?'**
  String get acctAddHowTitle;

  /// No description provided for @acctAddFromPhone.
  ///
  /// In en, this message translates to:
  /// **'From my phone'**
  String get acctAddFromPhone;

  /// No description provided for @acctAddFromPhoneSub.
  ///
  /// In en, this message translates to:
  /// **'Recommended — QR code to the full panel (add, edit, reload)'**
  String get acctAddFromPhoneSub;

  /// No description provided for @acctAddWithRemote.
  ///
  /// In en, this message translates to:
  /// **'With the remote'**
  String get acctAddWithRemote;

  /// No description provided for @acctAddWithRemoteSub.
  ///
  /// In en, this message translates to:
  /// **'Key-by-key typing'**
  String get acctAddWithRemoteSub;

  /// No description provided for @acctDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{label}” and its credentials will be erased permanently.'**
  String acctDeleteBody(String label);

  /// No description provided for @acctDeleteListGone.
  ///
  /// In en, this message translates to:
  /// **'The downloaded playlist goes with it ({size} freed).'**
  String acctDeleteListGone(String size);

  /// No description provided for @acctDeleteNoList.
  ///
  /// In en, this message translates to:
  /// **'No downloaded playlist to erase for this account.'**
  String get acctDeleteNoList;

  /// No description provided for @acctDeleteKept.
  ///
  /// In en, this message translates to:
  /// **'Favorites, resume points and finished downloads are kept.'**
  String get acctDeleteKept;

  /// No description provided for @acctDeletedWithSize.
  ///
  /// In en, this message translates to:
  /// **'✅ “{label}” deleted — {size} freed'**
  String acctDeletedWithSize(String label, String size);

  /// No description provided for @acctDeleted.
  ///
  /// In en, this message translates to:
  /// **'✅ “{label}” deleted'**
  String acctDeleted(String label);

  /// No description provided for @acctAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get acctAdd;

  /// No description provided for @acctEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No account set up'**
  String get acctEmptyTitle;

  /// No description provided for @acctEmptySubTv.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with your phone to set up your playlist without typing on the D-pad.'**
  String get acctEmptySubTv;

  /// No description provided for @acctEmptySubPhone.
  ///
  /// In en, this message translates to:
  /// **'Add a full M3U URL or an Xtream Codes account to start streaming.'**
  String get acctEmptySubPhone;

  /// No description provided for @acctEmptyCtaTv.
  ///
  /// In en, this message translates to:
  /// **'Set up from my phone'**
  String get acctEmptyCtaTv;

  /// No description provided for @acctEmptyCtaPhone.
  ///
  /// In en, this message translates to:
  /// **'Add a playlist'**
  String get acctEmptyCtaPhone;

  /// No description provided for @acctMainAccount.
  ///
  /// In en, this message translates to:
  /// **'MAIN ACCOUNT'**
  String get acctMainAccount;

  /// No description provided for @acctListsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} playlists'**
  String acctListsCount(int count);

  /// No description provided for @acctStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'{loaded}/{total} · {inProgress} in progress…'**
  String acctStatusInProgress(int loaded, int total, int inProgress);

  /// No description provided for @acctStatusWithFailed.
  ///
  /// In en, this message translates to:
  /// **'{base} · {failed} failed'**
  String acctStatusWithFailed(String base, int failed);

  /// No description provided for @acctStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'{loaded}/{total} · {failed} failed'**
  String acctStatusFailed(int loaded, int total, int failed);

  /// No description provided for @acctStatusLoaded.
  ///
  /// In en, this message translates to:
  /// **'✓ {loaded}/{total} loaded'**
  String acctStatusLoaded(int loaded, int total);

  /// No description provided for @acctReloadedFor.
  ///
  /// In en, this message translates to:
  /// **'✅ Playlist reloaded for {label}'**
  String acctReloadedFor(String label);

  /// No description provided for @commonFailedWith.
  ///
  /// In en, this message translates to:
  /// **'❌ Failed: {reason}'**
  String commonFailedWith(String reason);

  /// No description provided for @acctReloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Reload?'**
  String get acctReloadTitle;

  /// No description provided for @acctReloadBody.
  ///
  /// In en, this message translates to:
  /// **'The playlist for “{label}” was downloaded {age} ago.\nReload it from the server anyway?'**
  String acctReloadBody(String label, String age);

  /// No description provided for @acctReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get acctReload;

  /// No description provided for @acctDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get acctDownloading;

  /// No description provided for @acctReloadPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Reload the playlist'**
  String get acctReloadPlaylist;

  /// No description provided for @acctChipAvailable.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE'**
  String get acctChipAvailable;

  /// No description provided for @acctChipDownloading.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADING…'**
  String get acctChipDownloading;

  /// No description provided for @acctChipLoading.
  ///
  /// In en, this message translates to:
  /// **'LOADING…'**
  String get acctChipLoading;

  /// No description provided for @acctChipError.
  ///
  /// In en, this message translates to:
  /// **'ERROR'**
  String get acctChipError;

  /// No description provided for @acctChipNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'NOT LOADED'**
  String get acctChipNotLoaded;

  /// No description provided for @acctChipExpired.
  ///
  /// In en, this message translates to:
  /// **'EXPIRED'**
  String get acctChipExpired;

  /// No description provided for @acctChipExpiresToday.
  ///
  /// In en, this message translates to:
  /// **'EXPIRES TODAY'**
  String get acctChipExpiresToday;

  /// No description provided for @acctChipExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'EXPIRES IN {days} D'**
  String acctChipExpiresIn(int days);

  /// No description provided for @acctCountFilms.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get acctCountFilms;

  /// No description provided for @acctCountSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get acctCountSeries;

  /// No description provided for @acctCountTv.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get acctCountTv;

  /// No description provided for @acctStartupTime.
  ///
  /// In en, this message translates to:
  /// **'start {seconds} s'**
  String acctStartupTime(String seconds);

  /// No description provided for @acctM3uSize.
  ///
  /// In en, this message translates to:
  /// **'M3U size'**
  String get acctM3uSize;

  /// No description provided for @acctCacheAge.
  ///
  /// In en, this message translates to:
  /// **'Cache age'**
  String get acctCacheAge;

  /// No description provided for @acctNoCache.
  ///
  /// In en, this message translates to:
  /// **'No cache'**
  String get acctNoCache;

  /// No description provided for @acctAgeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get acctAgeJustNow;

  /// No description provided for @acctAgeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String acctAgeMinutes(int count);

  /// No description provided for @acctAgeHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String acctAgeHours(int count);

  /// No description provided for @acctAgeDays.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String acctAgeDays(int count);

  /// No description provided for @acctXtreamLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading Xtream info…'**
  String get acctXtreamLoading;

  /// No description provided for @acctXtreamUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Xtream info unavailable'**
  String get acctXtreamUnavailable;

  /// No description provided for @acctExpiration.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get acctExpiration;

  /// No description provided for @acctConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get acctConnections;

  /// No description provided for @acctExpiryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get acctExpiryUnknown;

  /// No description provided for @acctExpiryPast.
  ///
  /// In en, this message translates to:
  /// **'Expired ({days} d)'**
  String acctExpiryPast(int days);

  /// No description provided for @acctExpiryToday.
  ///
  /// In en, this message translates to:
  /// **'Expires today'**
  String get acctExpiryToday;

  /// No description provided for @acctExpiryTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Expires tomorrow'**
  String get acctExpiryTomorrow;

  /// No description provided for @acctExpiryInDays.
  ///
  /// In en, this message translates to:
  /// **'In {days} days'**
  String acctExpiryInDays(int days);

  /// No description provided for @unitBytes.
  ///
  /// In en, this message translates to:
  /// **'{value} B'**
  String unitBytes(String value);

  /// No description provided for @unitKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{value} kB'**
  String unitKilobytes(String value);

  /// No description provided for @unitMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String unitMegabytes(String value);

  /// No description provided for @unitGigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String unitGigabytes(String value);

  /// No description provided for @acctAgeHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h{minutes}'**
  String acctAgeHoursMinutes(int hours, String minutes);

  /// No description provided for @acctAgeMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count}min'**
  String acctAgeMinutesShort(int count);

  /// No description provided for @homeExitSearch.
  ///
  /// In en, this message translates to:
  /// **'Leave search'**
  String get homeExitSearch;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search the playlist…'**
  String get homeSearchHint;

  /// No description provided for @homeTabSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get homeTabSeries;

  /// No description provided for @homeTabMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get homeTabMovies;

  /// No description provided for @homeTabTv.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get homeTabTv;

  /// No description provided for @homeEmptyMovies.
  ///
  /// In en, this message translates to:
  /// **'No movies'**
  String get homeEmptyMovies;

  /// No description provided for @homeEmptySeries.
  ///
  /// In en, this message translates to:
  /// **'No series'**
  String get homeEmptySeries;

  /// No description provided for @homeEmptyTv.
  ///
  /// In en, this message translates to:
  /// **'No channels'**
  String get homeEmptyTv;

  /// No description provided for @homeEmptySub.
  ///
  /// In en, this message translates to:
  /// **'None of your playlists contains any. Reload a playlist or add an account.'**
  String get homeEmptySub;

  /// No description provided for @homeEmptyCta.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts'**
  String get homeEmptyCta;

  /// No description provided for @homeSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// No description provided for @homeResume.
  ///
  /// In en, this message translates to:
  /// **'RESUME'**
  String get homeResume;

  /// No description provided for @homeResumeChannel.
  ///
  /// In en, this message translates to:
  /// **'RESUME CHANNEL'**
  String get homeResumeChannel;

  /// No description provided for @searchNoTitleFound.
  ///
  /// In en, this message translates to:
  /// **'No title found'**
  String get searchNoTitleFound;

  /// No description provided for @searchNoTitleSub.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your playlists for “{query}”. Try another keyword or check the spelling.'**
  String searchNoTitleSub(String query);

  /// No description provided for @searchKeepTyping.
  ///
  /// In en, this message translates to:
  /// **'Keep typing…'**
  String get searchKeepTyping;

  /// No description provided for @searchKeepTypingSub.
  ///
  /// In en, this message translates to:
  /// **'At least {count} letters to search a movie or a series. Channels can be searched from the very first letter.'**
  String searchKeepTypingSub(int count);

  /// No description provided for @searchFromPerson.
  ///
  /// In en, this message translates to:
  /// **'By {name}, in your playlists'**
  String searchFromPerson(String name);

  /// No description provided for @searchOnTmdbMissing.
  ///
  /// In en, this message translates to:
  /// **'On TMDB, missing from your playlists'**
  String get searchOnTmdbMissing;

  /// No description provided for @searchNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'NOT AVAILABLE'**
  String get searchNotAvailable;

  /// No description provided for @searchTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search your playlist'**
  String get searchTypeToSearch;

  /// No description provided for @searchTypesLine.
  ///
  /// In en, this message translates to:
  /// **'Movies · Series · Channels'**
  String get searchTypesLine;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchRecent;

  /// No description provided for @searchClearHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get searchClearHistoryTitle;

  /// No description provided for @searchClearHistoryOne.
  ///
  /// In en, this message translates to:
  /// **'The last search will be removed.'**
  String get searchClearHistoryOne;

  /// No description provided for @searchClearHistoryMany.
  ///
  /// In en, this message translates to:
  /// **'The last {count} searches will be removed.'**
  String searchClearHistoryMany(int count);

  /// No description provided for @searchClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get searchClearConfirm;

  /// No description provided for @searchHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'History cleared'**
  String get searchHistoryCleared;

  /// No description provided for @cardPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get cardPlay;

  /// No description provided for @cardResumeFrom.
  ///
  /// In en, this message translates to:
  /// **'Resume from {position}'**
  String cardResumeFrom(String position);

  /// No description provided for @cardPlayFromStart.
  ///
  /// In en, this message translates to:
  /// **'Play from the start'**
  String get cardPlayFromStart;

  /// No description provided for @cardForgetResume.
  ///
  /// In en, this message translates to:
  /// **'Forget the resume point'**
  String get cardForgetResume;

  /// No description provided for @cardForgetResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget the resume point?'**
  String get cardForgetResumeTitle;

  /// No description provided for @cardForgetResumeQuestion.
  ///
  /// In en, this message translates to:
  /// **'The playback position for this title will be forgotten.'**
  String get cardForgetResumeQuestion;

  /// No description provided for @cardForgetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get cardForgetConfirm;

  /// No description provided for @cardResumeForgotten.
  ///
  /// In en, this message translates to:
  /// **'Resume point forgotten'**
  String get cardResumeForgotten;

  /// No description provided for @cardDetails.
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get cardDetails;

  /// No description provided for @castChannelsStereo.
  ///
  /// In en, this message translates to:
  /// **'stereo'**
  String get castChannelsStereo;

  /// No description provided for @castChannelsMono.
  ///
  /// In en, this message translates to:
  /// **'mono'**
  String get castChannelsMono;

  /// No description provided for @castChannelsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String castChannelsCount(int count);

  /// No description provided for @castAudioTrackFallback.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get castAudioTrackFallback;

  /// No description provided for @castAudioWarnPartial.
  ///
  /// In en, this message translates to:
  /// **'The TV will not decode every track of this stream. The app will ask it for: {track}. If the sound is still missing, the receiver kept its default track.'**
  String castAudioWarnPartial(String track);

  /// No description provided for @castAudioWarnSingle.
  ///
  /// In en, this message translates to:
  /// **'The sound of this stream is {detail}: the TV receiver cannot decode it (picture without sound). The app cannot convert it.'**
  String castAudioWarnSingle(String detail);

  /// No description provided for @castAudioWarnNone.
  ///
  /// In en, this message translates to:
  /// **'No audio track of this stream can be decoded by the TV receiver ({detail}): picture without sound. Another version of the same title, in AAC, would work.'**
  String castAudioWarnNone(String detail);

  /// No description provided for @castReceiverNoTracks.
  ///
  /// In en, this message translates to:
  /// **'no track announced'**
  String get castReceiverNoTracks;

  /// No description provided for @castReceiverNoAudio.
  ///
  /// In en, this message translates to:
  /// **'{count} track(s), no audio'**
  String castReceiverNoAudio(int count);

  /// No description provided for @castReceiverAudioSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} audio: {labels}'**
  String castReceiverAudioSummary(int count, String labels);

  /// No description provided for @castNoWifi.
  ///
  /// In en, this message translates to:
  /// **'The phone is not on a Wi-Fi network: the Chromecast cannot fetch the file. Connect it to the same network as the TV.'**
  String get castNoWifi;

  /// No description provided for @castNotStreamable.
  ///
  /// In en, this message translates to:
  /// **'This address cannot be cast (neither http nor https).'**
  String get castNotStreamable;

  /// No description provided for @castCannotVerify.
  ///
  /// In en, this message translates to:
  /// **'The stream cannot be checked from this network. Try again in a moment.'**
  String get castCannotVerify;

  /// No description provided for @castTlsRefused.
  ///
  /// In en, this message translates to:
  /// **'The provider uses a certificate the Chromecast refuses (the app accepts it). This stream cannot be cast.'**
  String get castTlsRefused;

  /// No description provided for @castUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The provider\'s server does not answer from this network.'**
  String get castUnreachable;

  /// No description provided for @castNeedsAuth.
  ///
  /// In en, this message translates to:
  /// **'This stream cannot be cast: the provider requires an identification the Chromecast cannot pass on.'**
  String get castNeedsAuth;

  /// No description provided for @castNotHls.
  ///
  /// In en, this message translates to:
  /// **'The provider does not offer this stream in a format the Chromecast can read (HLS).'**
  String get castNotHls;

  /// No description provided for @castHttpRefused.
  ///
  /// In en, this message translates to:
  /// **'This stream cannot be cast: the provider refuses a request without the app\'s IPTV profile (HTTP response {code}), which the Chromecast cannot imitate.'**
  String castHttpRefused(int code);

  /// No description provided for @castNoCors.
  ///
  /// In en, this message translates to:
  /// **'This stream cannot be cast: the provider does not allow playback from a browser (no CORS header), and that is how the Chromecast reads HLS.'**
  String get castNoCors;

  /// No description provided for @castNoticePlaying.
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String castNoticePlaying(String device);

  /// No description provided for @castNoticePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused on {device}'**
  String castNoticePaused(String device);

  /// No description provided for @castIdleFinished.
  ///
  /// In en, this message translates to:
  /// **'Playback finished on the TV.'**
  String get castIdleFinished;

  /// No description provided for @castIdleError.
  ///
  /// In en, this message translates to:
  /// **'The TV could not play this stream (format or address refused by the receiver).'**
  String get castIdleError;

  /// No description provided for @castIdleInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Casting interrupted by the TV.'**
  String get castIdleInterrupted;

  /// No description provided for @perrTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The stream stopped responding (timed out).'**
  String get perrTimedOut;

  /// No description provided for @perrConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to the server. Check your network.'**
  String get perrConnectionFailed;

  /// No description provided for @perrConnectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer.'**
  String get perrConnectionTimeout;

  /// No description provided for @perrBadHttpStatus.
  ///
  /// In en, this message translates to:
  /// **'The server refused the stream (HTTP error). Check the account or try again later.'**
  String get perrBadHttpStatus;

  /// No description provided for @perrFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Stream not found on the server.'**
  String get perrFileNotFound;

  /// No description provided for @perrNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Access to the stream refused.'**
  String get perrNoPermission;

  /// No description provided for @perrCleartextNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted connection refused by the system.'**
  String get perrCleartextNotPermitted;

  /// No description provided for @perrInvalidContentType.
  ///
  /// In en, this message translates to:
  /// **'The server is not returning a video (unexpected content type).'**
  String get perrInvalidContentType;

  /// No description provided for @perrPositionOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Playback position outside the stream.'**
  String get perrPositionOutOfRange;

  /// No description provided for @perrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network playback error.'**
  String get perrNetwork;

  /// No description provided for @perrBehindLiveWindow.
  ///
  /// In en, this message translates to:
  /// **'Too far behind the live edge: jumping back to live.'**
  String get perrBehindLiveWindow;

  /// No description provided for @perrPlayerTimeout.
  ///
  /// In en, this message translates to:
  /// **'The player did not answer in time.'**
  String get perrPlayerTimeout;

  /// No description provided for @perrMalformed.
  ///
  /// In en, this message translates to:
  /// **'Unreadable stream (corrupted or unexpected data).'**
  String get perrMalformed;

  /// No description provided for @perrUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Stream format not supported.'**
  String get perrUnsupportedFormat;

  /// No description provided for @perrDecoderInit.
  ///
  /// In en, this message translates to:
  /// **'Cannot initialize the video decoder.'**
  String get perrDecoderInit;

  /// No description provided for @perrDecodingFailed.
  ///
  /// In en, this message translates to:
  /// **'Decoding failed: the stream may be damaged.'**
  String get perrDecodingFailed;

  /// No description provided for @perrExceedsCapabilities.
  ///
  /// In en, this message translates to:
  /// **'This stream exceeds the device capabilities (resolution or bitrate).'**
  String get perrExceedsCapabilities;

  /// No description provided for @perrCodecUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Codec not supported by this device.'**
  String get perrCodecUnsupported;

  /// No description provided for @perrAudioOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio output unavailable (track or audio format not playable).'**
  String get perrAudioOutput;

  /// No description provided for @perrRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote player error.'**
  String get perrRemote;

  /// No description provided for @perrUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The player hit an unexpected error.'**
  String get perrUnexpected;

  /// No description provided for @perrDrm.
  ///
  /// In en, this message translates to:
  /// **'Protected content (DRM) cannot be played.'**
  String get perrDrm;

  /// No description provided for @perrDecodeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video decoding failed.'**
  String get perrDecodeVideo;

  /// No description provided for @perrCannotPlay.
  ///
  /// In en, this message translates to:
  /// **'Playback failed.'**
  String get perrCannotPlay;

  /// No description provided for @perrCannotPlayWith.
  ///
  /// In en, this message translates to:
  /// **'Playback failed: {detail}'**
  String perrCannotPlayWith(String detail);

  /// No description provided for @relayBatteryPluggedOk.
  ///
  /// In en, this message translates to:
  /// **'The phone is plugged in, perfect for a movie.'**
  String get relayBatteryPluggedOk;

  /// No description provided for @relayBatteryPlugIfYouCan.
  ///
  /// In en, this message translates to:
  /// **'Plug the phone in if you can: converting uses a lot of battery.'**
  String get relayBatteryPlugIfYouCan;

  /// No description provided for @relayBatteryLow.
  ///
  /// In en, this message translates to:
  /// **'Battery at {percent}% — plug the phone in, casting depends on it.'**
  String relayBatteryLow(int percent);

  /// No description provided for @relayBatteryMid.
  ///
  /// In en, this message translates to:
  /// **'Battery at {percent}%. Plug the phone in if you can, converting uses a lot of battery.'**
  String relayBatteryMid(int percent);

  /// No description provided for @relayScreenOffOk.
  ///
  /// In en, this message translates to:
  /// **'You can turn the screen off: casting continues in the background.'**
  String get relayScreenOffOk;

  /// No description provided for @relayDeviceFallback.
  ///
  /// In en, this message translates to:
  /// **'the TV'**
  String get relayDeviceFallback;

  /// No description provided for @relayConsentWhat.
  ///
  /// In en, this message translates to:
  /// **'This TV cannot play the sound of this movie. The phone can adapt it while casting to {device}.'**
  String relayConsentWhat(String device);

  /// No description provided for @relayConsentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Adapt and cast'**
  String get relayConsentConfirm;

  /// No description provided for @playerLastEpisode.
  ///
  /// In en, this message translates to:
  /// **'Last available episode.'**
  String get playerLastEpisode;

  /// No description provided for @playerAudioTrackSwitched.
  ///
  /// In en, this message translates to:
  /// **'Incompatible audio track — switching to {track}'**
  String playerAudioTrackSwitched(String track);

  /// No description provided for @playerNoAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'No playable audio track in this file — playing without sound'**
  String get playerNoAudioTrack;

  /// No description provided for @playerReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting in 5 s… ({attempt}/{max})'**
  String playerReconnecting(int attempt, int max);

  /// No description provided for @playerRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get playerRetry;

  /// No description provided for @playerBuffering.
  ///
  /// In en, this message translates to:
  /// **'Buffering…'**
  String get playerBuffering;

  /// No description provided for @castOverlayBack.
  ///
  /// In en, this message translates to:
  /// **'Back (casting continues)'**
  String get castOverlayBack;

  /// No description provided for @castOverlayCastingOn.
  ///
  /// In en, this message translates to:
  /// **'CASTING TO {device}'**
  String castOverlayCastingOn(String device);

  /// No description provided for @castOverlayStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting on the TV…'**
  String get castOverlayStarting;

  /// No description provided for @castOverlayPlayingAt.
  ///
  /// In en, this message translates to:
  /// **'Playing · {position}'**
  String castOverlayPlayingAt(String position);

  /// No description provided for @castOverlayLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading on the TV…'**
  String get castOverlayLoading;

  /// No description provided for @castOverlayBack30.
  ///
  /// In en, this message translates to:
  /// **'Back 30 s'**
  String get castOverlayBack30;

  /// No description provided for @castOverlayPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get castOverlayPause;

  /// No description provided for @castOverlayPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get castOverlayPlay;

  /// No description provided for @castOverlayForward30.
  ///
  /// In en, this message translates to:
  /// **'Forward 30 s'**
  String get castOverlayForward30;

  /// No description provided for @castOverlayReceiver.
  ///
  /// In en, this message translates to:
  /// **'Receiver · {detail}'**
  String castOverlayReceiver(String detail);

  /// No description provided for @castOverlayCastTitle.
  ///
  /// In en, this message translates to:
  /// **'Cast “{title}”'**
  String castOverlayCastTitle(String title);

  /// No description provided for @castOverlayResync.
  ///
  /// In en, this message translates to:
  /// **'Resynchronize picture and sound'**
  String get castOverlayResync;

  /// No description provided for @castOverlayResumeHere.
  ///
  /// In en, this message translates to:
  /// **'Resume on the phone'**
  String get castOverlayResumeHere;

  /// No description provided for @castOverlaySoundConverted.
  ///
  /// In en, this message translates to:
  /// **'Sound fully converted'**
  String get castOverlaySoundConverted;

  /// No description provided for @castOverlaySoundConverting.
  ///
  /// In en, this message translates to:
  /// **'Converting the sound'**
  String get castOverlaySoundConverting;

  /// No description provided for @castOverlayTvPlaysWhileConverting.
  ///
  /// In en, this message translates to:
  /// **'The TV plays while converting. Keep the app open.'**
  String get castOverlayTvPlaysWhileConverting;

  /// No description provided for @castOverlayPreparingFor.
  ///
  /// In en, this message translates to:
  /// **'PREPARING FOR {device}'**
  String castOverlayPreparingFor(String device);

  /// No description provided for @castOverlayCancelConversion.
  ///
  /// In en, this message translates to:
  /// **'Cancel the conversion'**
  String get castOverlayCancelConversion;

  /// No description provided for @castSheetNotCastable.
  ///
  /// In en, this message translates to:
  /// **'This stream cannot be cast.'**
  String get castSheetNotCastable;

  /// No description provided for @castSheetOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On {device}'**
  String castSheetOnDevice(String device);

  /// No description provided for @castSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Cast to…'**
  String get castSheetTitle;

  /// No description provided for @castSheetSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices on the network…'**
  String get castSheetSearching;

  /// No description provided for @castSheetChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the stream for {device}…'**
  String castSheetChecking(String device);

  /// No description provided for @castSheetChooseOther.
  ///
  /// In en, this message translates to:
  /// **'Choose another device'**
  String get castSheetChooseOther;

  /// No description provided for @castSheetConvertSound.
  ///
  /// In en, this message translates to:
  /// **'Convert the sound on the phone'**
  String get castSheetConvertSound;

  /// No description provided for @castSheetConvertSoundSub.
  ///
  /// In en, this message translates to:
  /// **'See what it involves before starting'**
  String get castSheetConvertSoundSub;

  /// No description provided for @castSheetCastAnyway.
  ///
  /// In en, this message translates to:
  /// **'Cast anyway'**
  String get castSheetCastAnyway;

  /// No description provided for @castSheetCastAnywaySub.
  ///
  /// In en, this message translates to:
  /// **'On {device} — picture without sound'**
  String castSheetCastAnywaySub(String device);

  /// No description provided for @castSheetStop.
  ///
  /// In en, this message translates to:
  /// **'Stop casting'**
  String get castSheetStop;

  /// No description provided for @castSheetStopSub.
  ///
  /// In en, this message translates to:
  /// **'Running on {device}'**
  String castSheetStopSub(String device);

  /// No description provided for @castSheetNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No Chromecast found. The phone must be on the same Wi-Fi as the TV, outside a guest network.'**
  String get castSheetNothingFound;

  /// No description provided for @castSheetSearchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get castSheetSearchAgain;

  /// No description provided for @tracksNoAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio track detected'**
  String get tracksNoAudio;

  /// No description provided for @tracksNoSubtitles.
  ///
  /// In en, this message translates to:
  /// **'No subtitle detected'**
  String get tracksNoSubtitles;

  /// No description provided for @tracksNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get tracksNone;

  /// No description provided for @tracksDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get tracksDisabled;

  /// No description provided for @langFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get langFrench;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get langSpanish;

  /// No description provided for @langGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get langGerman;

  /// No description provided for @langItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get langItalian;

  /// No description provided for @langPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get langPortuguese;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get langArabic;

  /// No description provided for @langRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get langRussian;

  /// No description provided for @langDutch.
  ///
  /// In en, this message translates to:
  /// **'Dutch'**
  String get langDutch;

  /// No description provided for @langJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get langJapanese;

  /// No description provided for @langChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get langChinese;

  /// No description provided for @langKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get langKorean;

  /// No description provided for @langTurkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get langTurkish;

  /// No description provided for @langPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get langPolish;

  /// No description provided for @statsDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding'**
  String get statsDecoding;

  /// No description provided for @statsHardwareWith.
  ///
  /// In en, this message translates to:
  /// **'hardware · {decoder}'**
  String statsHardwareWith(String decoder);

  /// No description provided for @statsHardware.
  ///
  /// In en, this message translates to:
  /// **'hardware'**
  String get statsHardware;

  /// No description provided for @statsResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get statsResolution;

  /// No description provided for @statsAnnouncedOversold.
  ///
  /// In en, this message translates to:
  /// **'{announced} — the playlist OVERSELLS'**
  String statsAnnouncedOversold(String announced);

  /// No description provided for @statsAnnouncedBetter.
  ///
  /// In en, this message translates to:
  /// **'{announced} · better than promised'**
  String statsAnnouncedBetter(String announced);

  /// No description provided for @statsYes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get statsYes;

  /// No description provided for @statsNo.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get statsNo;

  /// No description provided for @statsDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get statsDropped;

  /// No description provided for @statsBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get statsBitrate;

  /// No description provided for @statsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get statsNetwork;

  /// No description provided for @statsTransferred.
  ///
  /// In en, this message translates to:
  /// **'Transferred'**
  String get statsTransferred;

  /// No description provided for @statsStartup.
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get statsStartup;

  /// No description provided for @statsChannelsStereo.
  ///
  /// In en, this message translates to:
  /// **'stereo'**
  String get statsChannelsStereo;

  /// No description provided for @statsChannelsMono.
  ///
  /// In en, this message translates to:
  /// **'mono'**
  String get statsChannelsMono;

  /// No description provided for @statsChannelsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String statsChannelsCount(int count);

  /// No description provided for @statsStallsNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get statsStallsNone;

  /// No description provided for @statsStallsWithTime.
  ///
  /// In en, this message translates to:
  /// **'{count} ({seconds}s in total)'**
  String statsStallsWithTime(int count, int seconds);

  /// No description provided for @nextEpLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the next episode…'**
  String get nextEpLoading;

  /// No description provided for @nextEpTitle.
  ///
  /// In en, this message translates to:
  /// **'NEXT EPISODE'**
  String get nextEpTitle;

  /// No description provided for @nextEpPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get nextEpPlay;

  /// No description provided for @nextEpSeasonEnd.
  ///
  /// In en, this message translates to:
  /// **'END OF SEASON'**
  String get nextEpSeasonEnd;

  /// No description provided for @nextEpGoToSeason.
  ///
  /// In en, this message translates to:
  /// **'Go to season {season}?'**
  String nextEpGoToSeason(int season);

  /// No description provided for @nextEpGoToNextSeason.
  ///
  /// In en, this message translates to:
  /// **'Go to the next season?'**
  String get nextEpGoToNextSeason;

  /// No description provided for @nextEpBackToDetails.
  ///
  /// In en, this message translates to:
  /// **'Back to the details'**
  String get nextEpBackToDetails;

  /// No description provided for @nextEpSeriesOver.
  ///
  /// In en, this message translates to:
  /// **'SERIES FINISHED'**
  String get nextEpSeriesOver;

  /// No description provided for @nextEpSeriesOverSub.
  ///
  /// In en, this message translates to:
  /// **'You have watched the last available episode.'**
  String get nextEpSeriesOverSub;

  /// No description provided for @ctrlCast.
  ///
  /// In en, this message translates to:
  /// **'Cast to a Chromecast'**
  String get ctrlCast;

  /// No description provided for @ctrlPip.
  ///
  /// In en, this message translates to:
  /// **'Shrink to a window'**
  String get ctrlPip;

  /// No description provided for @ctrlOptions.
  ///
  /// In en, this message translates to:
  /// **'Playback options'**
  String get ctrlOptions;

  /// No description provided for @ctrlTracks.
  ///
  /// In en, this message translates to:
  /// **'Audio and subtitle tracks'**
  String get ctrlTracks;

  /// No description provided for @ctrlSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get ctrlSpeed;

  /// No description provided for @ctrlNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get ctrlNextEpisode;

  /// No description provided for @ctrlBadgeMovie.
  ///
  /// In en, this message translates to:
  /// **'MOVIE'**
  String get ctrlBadgeMovie;

  /// No description provided for @ctrlBadgeSeries.
  ///
  /// In en, this message translates to:
  /// **'SERIES'**
  String get ctrlBadgeSeries;

  /// No description provided for @ctrlUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get ctrlUnlock;

  /// No description provided for @optNextEpisodeSub.
  ///
  /// In en, this message translates to:
  /// **'Skip to the next episode'**
  String get optNextEpisodeSub;

  /// No description provided for @optTracksSub.
  ///
  /// In en, this message translates to:
  /// **'Audio language · turn subtitles on'**
  String get optTracksSub;

  /// No description provided for @optVideoInfo.
  ///
  /// In en, this message translates to:
  /// **'Video info'**
  String get optVideoInfo;

  /// No description provided for @optVideoInfoOn.
  ///
  /// In en, this message translates to:
  /// **'Shown · tap to hide'**
  String get optVideoInfoOn;

  /// No description provided for @optVideoInfoSub.
  ///
  /// In en, this message translates to:
  /// **'Decoding, resolution, frames/s, drops'**
  String get optVideoInfoSub;

  /// No description provided for @fitContainSub.
  ///
  /// In en, this message translates to:
  /// **'Whole picture · black bars possible'**
  String get fitContainSub;

  /// No description provided for @fitCoverSub.
  ///
  /// In en, this message translates to:
  /// **'Removes black bars · crops the edges'**
  String get fitCoverSub;

  /// No description provided for @fitFill.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fitFill;

  /// No description provided for @fitFillSub.
  ///
  /// In en, this message translates to:
  /// **'Fills everything · slightly distorted picture'**
  String get fitFillSub;

  /// No description provided for @ctrlCastActive.
  ///
  /// In en, this message translates to:
  /// **'Casting'**
  String get ctrlCastActive;

  /// No description provided for @ctrlLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get ctrlLock;

  /// No description provided for @ctrlBadgeLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get ctrlBadgeLive;

  /// No description provided for @ctrlBadgeReplay.
  ///
  /// In en, this message translates to:
  /// **'REPLAY'**
  String get ctrlBadgeReplay;

  /// No description provided for @optTitle.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get optTitle;

  /// No description provided for @optBackToVideo.
  ///
  /// In en, this message translates to:
  /// **'Back to video'**
  String get optBackToVideo;

  /// No description provided for @sheetClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sheetClose;

  /// No description provided for @bootSlowHint.
  ///
  /// In en, this message translates to:
  /// **'Loading is taking longer than usual. You can go in now: your lists will finish loading in the background.'**
  String get bootSlowHint;

  /// No description provided for @bootContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Go in without waiting'**
  String get bootContinueAnyway;

  /// No description provided for @bootStalledBody.
  ///
  /// In en, this message translates to:
  /// **'The main list has stopped making progress. It keeps loading in the background: try again in a moment, or check the account.'**
  String get bootStalledBody;

  /// No description provided for @playlistNoTitles.
  ///
  /// In en, this message translates to:
  /// **'This list contains no titles. Check the account, or try again later.'**
  String get playlistNoTitles;

  /// No description provided for @sheetCloseSub.
  ///
  /// In en, this message translates to:
  /// **'Closes without changing anything'**
  String get sheetCloseSub;

  /// No description provided for @optBackToVideoSub.
  ///
  /// In en, this message translates to:
  /// **'Closes this panel, playback continues'**
  String get optBackToVideoSub;

  /// No description provided for @optNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get optNextEpisode;

  /// No description provided for @optTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio & subtitle tracks'**
  String get optTracksTitle;

  /// No description provided for @optSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get optSpeedTitle;

  /// No description provided for @optFitTitle.
  ///
  /// In en, this message translates to:
  /// **'Picture format'**
  String get optFitTitle;

  /// No description provided for @optSpeedNormal.
  ///
  /// In en, this message translates to:
  /// **'1.0×  ·  Normal'**
  String get optSpeedNormal;

  /// No description provided for @castSheetDeviceFallback.
  ///
  /// In en, this message translates to:
  /// **'the TV'**
  String get castSheetDeviceFallback;

  /// No description provided for @statsDecodingPending.
  ///
  /// In en, this message translates to:
  /// **'in progress…'**
  String get statsDecodingPending;

  /// No description provided for @statsSoftware.
  ///
  /// In en, this message translates to:
  /// **'SOFTWARE'**
  String get statsSoftware;

  /// No description provided for @statsOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get statsOutput;

  /// No description provided for @statsCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get statsCodec;

  /// No description provided for @statsHdr.
  ///
  /// In en, this message translates to:
  /// **'HDR'**
  String get statsHdr;

  /// No description provided for @statsFps.
  ///
  /// In en, this message translates to:
  /// **'Frames/s'**
  String get statsFps;

  /// No description provided for @statsLost.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get statsLost;

  /// No description provided for @statsRendered.
  ///
  /// In en, this message translates to:
  /// **'Rendered'**
  String get statsRendered;

  /// No description provided for @statsBuffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get statsBuffer;

  /// No description provided for @statsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get statsAudio;

  /// No description provided for @statsStalls.
  ///
  /// In en, this message translates to:
  /// **'Stalls'**
  String get statsStalls;

  /// No description provided for @statsAnnouncedOk.
  ///
  /// In en, this message translates to:
  /// **'{announced} · as promised'**
  String statsAnnouncedOk(String announced);

  /// No description provided for @statsRenderedValue.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps'**
  String statsRenderedValue(String fps);

  /// No description provided for @statsRenderedVsAnnounced.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps (announced {announced})'**
  String statsRenderedVsAnnounced(String fps, String announced);

  /// No description provided for @statsSecondsValue.
  ///
  /// In en, this message translates to:
  /// **'{value} s'**
  String statsSecondsValue(String value);

  /// No description provided for @fitOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get fitOriginal;

  /// No description provided for @fitZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get fitZoom;

  /// No description provided for @playerRecovering.
  ///
  /// In en, this message translates to:
  /// **'Resuming playback… ({attempt}/{max})'**
  String playerRecovering(int attempt, int max);

  /// No description provided for @playerOtherTrack.
  ///
  /// In en, this message translates to:
  /// **'another track'**
  String get playerOtherTrack;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying…'**
  String get commonApplying;

  /// No description provided for @bkPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Encryption password'**
  String get bkPasswordTitle;

  /// No description provided for @bkPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a password — it will be asked for to restore the backup.'**
  String get bkPasswordHelp;

  /// No description provided for @bkPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get bkPasswordLabel;

  /// No description provided for @bkPasswordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get bkPasswordConfirmLabel;

  /// No description provided for @bkPasswordEmpty.
  ///
  /// In en, this message translates to:
  /// **'The password cannot be empty.'**
  String get bkPasswordEmpty;

  /// No description provided for @bkPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters.'**
  String get bkPasswordTooShort;

  /// No description provided for @bkPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords differ.'**
  String get bkPasswordMismatch;

  /// No description provided for @bkSave.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get bkSave;

  /// No description provided for @bkCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created'**
  String get bkCreated;

  /// No description provided for @bkCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a backup'**
  String get bkCreateTitle;

  /// No description provided for @bkCreateSub.
  ///
  /// In en, this message translates to:
  /// **'Encrypts your accounts, TMDB key, theme, favorites and progress into a .aether file.'**
  String get bkCreateSub;

  /// No description provided for @bkEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting…'**
  String get bkEncrypting;

  /// No description provided for @bkRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore a backup'**
  String get bkRestoreTitle;

  /// No description provided for @bkRestoreSub.
  ///
  /// In en, this message translates to:
  /// **'Pick a .aether file, enter your password, check the summary, apply.'**
  String get bkRestoreSub;

  /// No description provided for @bkRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get bkRestoring;

  /// No description provided for @bkImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import a .aether file'**
  String get bkImportFile;

  /// No description provided for @bkHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get bkHowTitle;

  /// No description provided for @bkHowBody.
  ///
  /// In en, this message translates to:
  /// **'• `.aether` file encrypted with AES-256-GCM + PBKDF2 (100k iterations).\n• Password chosen by you — the app stores it nowhere.\n• Location: Download/AetherStream/ (survives an uninstall).\n• Contents: IPTV accounts, TMDB key, theme, favorites, progress.\n• Excluded: downloads (too heavy), search history.\n• Importing overwrites the whole current configuration (irreversible).'**
  String get bkHowBody;

  /// No description provided for @bkRestorePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get bkRestorePasswordTitle;

  /// No description provided for @bkDecrypt.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get bkDecrypt;

  /// No description provided for @bkConfirmRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm the restore'**
  String get bkConfirmRestoreTitle;

  /// No description provided for @bkConfirmRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Your whole current state (accounts, TMDB key, theme, favorites, playback progress) will be OVERWRITTEN by this backup.\n\nThis cannot be undone. Continue?'**
  String get bkConfirmRestoreBody;

  /// No description provided for @bkRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get bkRestore;

  /// No description provided for @bkRestoreDone.
  ///
  /// In en, this message translates to:
  /// **'Restore succeeded'**
  String get bkRestoreDone;

  /// No description provided for @bkRestoreDoneSub.
  ///
  /// In en, this message translates to:
  /// **'The IPTV playlists will be downloaded again on the next start.'**
  String get bkRestoreDoneSub;

  /// No description provided for @regionApplied.
  ///
  /// In en, this message translates to:
  /// **'✅ Filter applied — catalog reloaded'**
  String get regionApplied;

  /// No description provided for @regionHelp.
  ///
  /// In en, this message translates to:
  /// **'Tick the languages/regions to HIDE from the catalog. French (|FR|), Québécois and VOSTFR content is always kept.'**
  String get regionHelp;

  /// No description provided for @regionApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying the filter…'**
  String get regionApplying;

  /// No description provided for @regionApplyingSub.
  ///
  /// In en, this message translates to:
  /// **'The catalog is being re-parsed. This may take a few seconds.'**
  String get regionApplyingSub;

  /// No description provided for @regionHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get regionHidden;

  /// No description provided for @regionVisible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get regionVisible;

  /// No description provided for @bkExportLocation.
  ///
  /// In en, this message translates to:
  /// **'Available in:\n/storage/emulated/0/Download/AetherStream/\n\nCopy this file to Drive, your PC, or another device to restore it later. Do not forget the password — it is stored nowhere.'**
  String get bkExportLocation;

  /// No description provided for @themeResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset the theme?'**
  String get themeResetTitle;

  /// No description provided for @themeResetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Every color and effect returns to its default value.'**
  String get themeResetQuestion;

  /// No description provided for @themeSectionPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get themeSectionPresets;

  /// No description provided for @themeSectionColors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get themeSectionColors;

  /// No description provided for @themeColorPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get themeColorPrimary;

  /// No description provided for @themeColorAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get themeColorAccent;

  /// No description provided for @themeColorTertiary.
  ///
  /// In en, this message translates to:
  /// **'Tertiary'**
  String get themeColorTertiary;

  /// No description provided for @themeSectionStateColors.
  ///
  /// In en, this message translates to:
  /// **'State colors'**
  String get themeSectionStateColors;

  /// No description provided for @themeColorFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite ❤'**
  String get themeColorFavorite;

  /// No description provided for @themeColorWarning.
  ///
  /// In en, this message translates to:
  /// **'Resume / Alert'**
  String get themeColorWarning;

  /// No description provided for @themeColorError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get themeColorError;

  /// No description provided for @themeColorSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get themeColorSuccess;

  /// No description provided for @themeSectionEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get themeSectionEffects;

  /// No description provided for @themeGlow.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get themeGlow;

  /// No description provided for @themeRadius.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get themeRadius;

  /// No description provided for @themeSectionMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get themeSectionMode;

  /// No description provided for @themeSectionPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get themeSectionPreview;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeModeSystem;

  /// No description provided for @themePreviewPlay.
  ///
  /// In en, this message translates to:
  /// **'▶  Play'**
  String get themePreviewPlay;

  /// No description provided for @xmltvUpdated.
  ///
  /// In en, this message translates to:
  /// **'✅ Channel guide updated'**
  String get xmltvUpdated;

  /// No description provided for @xmltvUpdateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The channel guide couldn\'t be updated right now. Try again later.'**
  String get xmltvUpdateUnavailable;

  /// No description provided for @xmltvUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'❌ Update failed: {reason}'**
  String xmltvUpdateFailed(String reason);

  /// No description provided for @xmltvNeverLoaded.
  ///
  /// In en, this message translates to:
  /// **'Never loaded'**
  String get xmltvNeverLoaded;

  /// No description provided for @xmltvJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get xmltvJustNow;

  /// No description provided for @xmltvChannelsAndAge.
  ///
  /// In en, this message translates to:
  /// **'{count} channels · {age}'**
  String xmltvChannelsAndAge(int count, String age);

  /// No description provided for @xmltvDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get xmltvDownloading;

  /// No description provided for @xmltvForceUpdate.
  ///
  /// In en, this message translates to:
  /// **'Force an update'**
  String get xmltvForceUpdate;

  /// No description provided for @xmltvHowBody.
  ///
  /// In en, this message translates to:
  /// **'• Public source: xmltvfr.fr (French DTT)\n• Covers the main French channels (TF1, France 2, M6, ARTE…)\n• Used for the “Now / Next” block and the replay grid'**
  String get xmltvHowBody;

  /// No description provided for @visualLangApplied.
  ///
  /// In en, this message translates to:
  /// **'Artwork in {language} — posters already on screen keep their language until the next reload.'**
  String visualLangApplied(String language);

  /// No description provided for @visualLangUiStaysFrench.
  ///
  /// In en, this message translates to:
  /// **'Posters, backdrops and texts coming from TMDB. The app interface follows the device language.'**
  String get visualLangUiStaysFrench;

  /// No description provided for @visualLangNote.
  ///
  /// In en, this message translates to:
  /// **'A poster provided by your IPTV playlist is never replaced: this choice only applies to artwork the app fetches itself.'**
  String get visualLangNote;

  /// No description provided for @aboutChecking.
  ///
  /// In en, this message translates to:
  /// **'🔍 Checking for updates…'**
  String get aboutChecking;

  /// No description provided for @aboutUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are up to date.'**
  String get aboutUpToDate;

  /// No description provided for @aboutCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Cannot check: {reason}'**
  String aboutCheckFailed(String reason);

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Android IPTV client — multi-account, EPG, replay, TMDB.'**
  String get aboutTagline;

  /// No description provided for @aboutCheckingShort.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get aboutCheckingShort;

  /// No description provided for @aboutCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheckUpdates;

  /// No description provided for @consoleNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No local network found. Connect the TV to Wi-Fi or Ethernet.'**
  String get consoleNoNetwork;

  /// No description provided for @consoleStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot start the local server: {reason}'**
  String consoleStartFailed(String reason);

  /// No description provided for @consoleOpenAddress.
  ///
  /// In en, this message translates to:
  /// **'Open this address in a browser\non a PC or a phone on the same network:'**
  String get consoleOpenAddress;

  /// No description provided for @consoleAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get consoleAddressCopied;

  /// No description provided for @consoleBackgroundNote.
  ///
  /// In en, this message translates to:
  /// **'The server stays alive in the background as long as you use the remote, even after leaving this screen. Stop it here when you are done (otherwise it closes after 30 min without use).'**
  String get consoleBackgroundNote;

  /// No description provided for @consoleStopServer.
  ///
  /// In en, this message translates to:
  /// **'Stop the server'**
  String get consoleStopServer;

  /// No description provided for @consoleActiveBanner.
  ///
  /// In en, this message translates to:
  /// **'Web console open: the app can be controlled from your local network'**
  String get consoleActiveBanner;

  /// No description provided for @failNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'NOT LOADED'**
  String get failNotLoaded;

  /// No description provided for @failNetwork.
  ///
  /// In en, this message translates to:
  /// **'NETWORK FAILED'**
  String get failNetwork;

  /// No description provided for @failPanelBusy.
  ///
  /// In en, this message translates to:
  /// **'PANEL BUSY'**
  String get failPanelBusy;

  /// No description provided for @failIncomplete.
  ///
  /// In en, this message translates to:
  /// **'INCOMPLETE LIST'**
  String get failIncomplete;

  /// No description provided for @failParse.
  ///
  /// In en, this message translates to:
  /// **'PARSING FAILED'**
  String get failParse;

  /// No description provided for @failNoData.
  ///
  /// In en, this message translates to:
  /// **'NO DATA'**
  String get failNoData;

  /// No description provided for @failExplainNever.
  ///
  /// In en, this message translates to:
  /// **'This playlist has not been loaded yet.'**
  String get failExplainNever;

  /// No description provided for @failExplainUnloaded.
  ///
  /// In en, this message translates to:
  /// **'Memory freed; the playlist comes back as soon as it is needed.'**
  String get failExplainUnloaded;

  /// No description provided for @failExplainDeferred.
  ///
  /// In en, this message translates to:
  /// **'Update postponed until after start-up.'**
  String get failExplainDeferred;

  /// No description provided for @failExplainPanelBusy.
  ///
  /// In en, this message translates to:
  /// **'The provider refused: too many simultaneous connections.'**
  String get failExplainPanelBusy;

  /// No description provided for @failExplainIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The catalog arrived incomplete; the previous one was kept.'**
  String get failExplainIncomplete;

  /// No description provided for @failExplainParse.
  ///
  /// In en, this message translates to:
  /// **'The playlist could not be parsed.'**
  String get failExplainParse;

  /// No description provided for @failExplainCacheGone.
  ///
  /// In en, this message translates to:
  /// **'The parsed cache is unreadable.'**
  String get failExplainCacheGone;

  /// No description provided for @failExplainNoSource.
  ///
  /// In en, this message translates to:
  /// **'No cached data for this playlist.'**
  String get failExplainNoSource;

  /// No description provided for @reloadBatchAllOk.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} playlist(s) reloaded'**
  String reloadBatchAllOk(int count);

  /// No description provided for @reloadBatchAllFailed.
  ///
  /// In en, this message translates to:
  /// **'❌ No playlist reloaded — {names}'**
  String reloadBatchAllFailed(String names);

  /// No description provided for @reloadBatchMixed.
  ///
  /// In en, this message translates to:
  /// **'⚠️ {ok} reloaded, {failed} failed: {names}'**
  String reloadBatchMixed(int ok, int failed, String names);

  /// No description provided for @reloadDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed (check the URL or the connection).'**
  String get reloadDownloadFailed;

  /// No description provided for @playlistNotAList.
  ///
  /// In en, this message translates to:
  /// **'The server did not return a usable playlist. Check the playlist address.'**
  String get playlistNotAList;

  /// No description provided for @reloadParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Parsing the playlist failed.'**
  String get reloadParseFailed;

  /// No description provided for @bkPartTmdbKey.
  ///
  /// In en, this message translates to:
  /// **'TMDB key'**
  String get bkPartTmdbKey;

  /// No description provided for @bkPartTheme.
  ///
  /// In en, this message translates to:
  /// **'theme'**
  String get bkPartTheme;

  /// No description provided for @bkPartHiddenRegions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hidden language} other{{count} hidden languages}}'**
  String bkPartHiddenRegions(int count);

  /// No description provided for @bkPasswordEmptyError.
  ///
  /// In en, this message translates to:
  /// **'The password cannot be empty.'**
  String get bkPasswordEmptyError;

  /// No description provided for @bkNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'Backup created by a newer version of the app; an update is required.'**
  String get bkNewerVersion;

  /// No description provided for @bkWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password, or the backup file is corrupted.'**
  String get bkWrongPassword;

  /// No description provided for @bkNoReadableAccount.
  ///
  /// In en, this message translates to:
  /// **'None of the accounts in this backup could be read: nothing was changed.'**
  String get bkNoReadableAccount;

  /// No description provided for @castDiscoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Discovery failed on this network. The phone must be on the same Wi-Fi as the TV, outside a guest network.'**
  String get castDiscoveryFailed;

  /// No description provided for @castDeviceNotResponding.
  ///
  /// In en, this message translates to:
  /// **'{device} is not answering. Check that it is on and on the same network.'**
  String castDeviceNotResponding(String device);

  /// No description provided for @castConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to {device}.'**
  String castConnectFailed(String device);

  /// No description provided for @castStreamRefused.
  ///
  /// In en, this message translates to:
  /// **'The TV did not accept this stream.'**
  String get castStreamRefused;

  /// No description provided for @castConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection to the TV lost.'**
  String get castConnectionLost;

  /// No description provided for @relayNoNetworkAddress.
  ///
  /// In en, this message translates to:
  /// **'No network address: the TV could not reach the phone.'**
  String get relayNoNetworkAddress;

  /// No description provided for @relayStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The conversion could not start.'**
  String get relayStartFailed;

  /// No description provided for @relayOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot open the relay on the local network.'**
  String get relayOpenFailed;

  /// No description provided for @relayTooSlow.
  ///
  /// In en, this message translates to:
  /// **'The beginning of the movie did not arrive in time: the source is too slow to be converted.'**
  String get relayTooSlow;

  /// No description provided for @dlQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued…'**
  String get dlQueued;

  /// No description provided for @dlFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing…'**
  String get dlFinalizing;

  /// No description provided for @dlActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads'**
  String dlActiveCount(int count);

  /// No description provided for @updGithubHttp.
  ///
  /// In en, this message translates to:
  /// **'GitHub answered HTTP {code}.'**
  String updGithubHttp(int code);

  /// No description provided for @updNoApk.
  ///
  /// In en, this message translates to:
  /// **'The latest release ({tag}) contains no APK.'**
  String updNoApk(String tag);

  /// No description provided for @updTimeout.
  ///
  /// In en, this message translates to:
  /// **'GitHub did not answer in time.'**
  String get updTimeout;

  /// No description provided for @updUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach GitHub. Check your connection.'**
  String get updUnreachable;

  /// No description provided for @updInstallDenied.
  ///
  /// In en, this message translates to:
  /// **'Installation permission denied'**
  String get updInstallDenied;

  /// No description provided for @updNoApkForDevice.
  ///
  /// In en, this message translates to:
  /// **'The latest release ({tag}) has no version for this device.'**
  String updNoApkForDevice(String tag);

  /// No description provided for @updUnverifiable.
  ///
  /// In en, this message translates to:
  /// **'This update cannot be verified, so it was not installed.'**
  String get updUnverifiable;

  /// No description provided for @updCorrupted.
  ///
  /// In en, this message translates to:
  /// **'The downloaded update is damaged. Try again.'**
  String get updCorrupted;

  /// No description provided for @failOnDisk.
  ///
  /// In en, this message translates to:
  /// **'ON DISK'**
  String get failOnDisk;

  /// No description provided for @failWaiting.
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get failWaiting;

  /// No description provided for @failCacheGone.
  ///
  /// In en, this message translates to:
  /// **'CACHE LOST'**
  String get failCacheGone;

  /// No description provided for @failBadAccount.
  ///
  /// In en, this message translates to:
  /// **'INVALID ACCOUNT'**
  String get failBadAccount;

  /// No description provided for @failExplainNetwork.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable.'**
  String get failExplainNetwork;

  /// No description provided for @failExplainBadAccount.
  ///
  /// In en, this message translates to:
  /// **'Invalid account configuration.'**
  String get failExplainBadAccount;

  /// No description provided for @bkPartAccounts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}}'**
  String bkPartAccounts(int count);

  /// No description provided for @bkPartOptimization.
  ///
  /// In en, this message translates to:
  /// **'optimization'**
  String get bkPartOptimization;

  /// No description provided for @bkPartFavorites.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 favorite} other{{count} favorites}}'**
  String bkPartFavorites(int count);

  /// No description provided for @bkPartProgress.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 resume point} other{{count} resume points}}'**
  String bkPartProgress(int count);

  /// No description provided for @bkEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty backup'**
  String get bkEmpty;

  /// No description provided for @relayFormatFailed.
  ///
  /// In en, this message translates to:
  /// **'The conversion failed: the phone cannot read this format back.'**
  String get relayFormatFailed;

  /// No description provided for @dlFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dlFilterAll;

  /// No description provided for @dlFilterActive.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get dlFilterActive;

  /// No description provided for @dlFilterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get dlFilterCompleted;

  /// No description provided for @dlFilterErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get dlFilterErrors;

  /// No description provided for @dlSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search a download'**
  String get dlSearchHint;

  /// No description provided for @dlSearchOpen.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get dlSearchOpen;

  /// No description provided for @dlSearchClose.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get dlSearchClose;

  /// No description provided for @dlEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Start a download from a movie or series page — it will show up here with its progress.'**
  String get dlEmptyHint;

  /// No description provided for @dlNoSearchResult.
  ///
  /// In en, this message translates to:
  /// **'No download matches this search.'**
  String get dlNoSearchResult;

  /// No description provided for @dlNoneInFilter.
  ///
  /// In en, this message translates to:
  /// **'No download in “{filter}”.'**
  String dlNoneInFilter(String filter);

  /// No description provided for @dlStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop the download?'**
  String get dlStopTitle;

  /// No description provided for @dlStopBody.
  ///
  /// In en, this message translates to:
  /// **'What is already downloaded is kept: you will be able to resume where it stopped.'**
  String get dlStopBody;

  /// No description provided for @dlStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get dlStop;

  /// No description provided for @dlActionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get dlActionPlay;

  /// No description provided for @dlActionMonitor.
  ///
  /// In en, this message translates to:
  /// **'See the progress'**
  String get dlActionMonitor;

  /// No description provided for @dlActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Stop the download'**
  String get dlActionCancel;

  /// No description provided for @dlActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dlActionDelete;

  /// No description provided for @dlRetriedTimes.
  ///
  /// In en, this message translates to:
  /// **'restarted ×{count}'**
  String dlRetriedTimes(int count);

  /// No description provided for @dlAlreadyDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Already downloaded'**
  String get dlAlreadyDownloaded;

  /// No description provided for @dlSee.
  ///
  /// In en, this message translates to:
  /// **'See'**
  String get dlSee;

  /// No description provided for @dlStorageDenied.
  ///
  /// In en, this message translates to:
  /// **'Storage permission denied: the download cannot start.'**
  String get dlStorageDenied;

  /// No description provided for @dlOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get dlOpenSettings;

  /// No description provided for @bootFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Start-up interrupted'**
  String get bootFailedTitle;

  /// No description provided for @bootFailedBody.
  ///
  /// In en, this message translates to:
  /// **'The app could not load your playlist.'**
  String get bootFailedBody;

  /// No description provided for @bootCheckAccounts.
  ///
  /// In en, this message translates to:
  /// **'Check the accounts'**
  String get bootCheckAccounts;

  /// No description provided for @bootNoAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'No account set up'**
  String get bootNoAccountTitle;

  /// No description provided for @bootNoAccountTv.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR code with your phone to manage your playlists without typing on the remote.'**
  String get bootNoAccountTv;

  /// No description provided for @bootNoAccountPhone.
  ///
  /// In en, this message translates to:
  /// **'Add an account to get started.'**
  String get bootNoAccountPhone;

  /// No description provided for @bootConfigureFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Set up from my phone'**
  String get bootConfigureFromPhone;

  /// No description provided for @bootConfigureAccounts.
  ///
  /// In en, this message translates to:
  /// **'Set up the accounts'**
  String get bootConfigureAccounts;

  /// No description provided for @bootRestoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore a backup'**
  String get bootRestoreBackup;

  /// No description provided for @onbPlaylistSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ Playlist saved'**
  String get onbPlaylistSaved;

  /// No description provided for @onbTmdbSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ TMDB key saved'**
  String get onbTmdbSaved;

  /// No description provided for @onbHasBackup.
  ///
  /// In en, this message translates to:
  /// **'I already have a backup (.aether)'**
  String get onbHasBackup;

  /// No description provided for @onbAddPlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a playlist'**
  String get onbAddPlaylistTitle;

  /// No description provided for @onbAddPlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'Go to ⚙️ Settings → IPTV accounts to enter a full M3U URL OR an Xtream Codes account (server + credentials).'**
  String get onbAddPlaylistBody;

  /// No description provided for @onbTmdbTitle.
  ///
  /// In en, this message translates to:
  /// **'Posters and synopses (optional)'**
  String get onbTmdbTitle;

  /// No description provided for @onbTmdbBody.
  ///
  /// In en, this message translates to:
  /// **'Generate a free TMDB Bearer Token on themoviedb.org and paste it into Settings → TMDB API key to enrich your movies and series.'**
  String get onbTmdbBody;

  /// No description provided for @onbCardMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'The ⋯ menu on thumbnails'**
  String get onbCardMenuTitle;

  /// No description provided for @onbCardMenuBody.
  ///
  /// In en, this message translates to:
  /// **'Long-press a poster — or tap the ⋯ at the top left — to Play, Resume, add to favorites, download or forget a resume point, without opening the details page.'**
  String get onbCardMenuBody;

  /// No description provided for @onbWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to AetherStream'**
  String get onbWelcomeTitle;

  /// No description provided for @onbWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Multi-account IPTV client to watch movies, series and live channels from your subscriptions.'**
  String get onbWelcomeBody;

  /// No description provided for @onbConfigureFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Set it up from your phone'**
  String get onbConfigureFromPhone;

  /// No description provided for @onbQrBody.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code: you can add your playlist, your TMDB key and set up the rest from your browser — typing on the D-pad would be long and tedious.'**
  String get onbQrBody;

  /// No description provided for @actorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Error: profile not found on TMDB.'**
  String get actorNotFound;

  /// No description provided for @actorFilmographyDirecting.
  ///
  /// In en, this message translates to:
  /// **'Filmography (Directing)'**
  String get actorFilmographyDirecting;

  /// No description provided for @actorFilmographyRoles.
  ///
  /// In en, this message translates to:
  /// **'Filmography (Roles)'**
  String get actorFilmographyRoles;

  /// No description provided for @actorDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get actorDirector;

  /// No description provided for @actorRole.
  ///
  /// In en, this message translates to:
  /// **'Role: {character}'**
  String actorRole(String character);

  /// No description provided for @detActorNotFound.
  ///
  /// In en, this message translates to:
  /// **'TMDB found no profile for {name}.'**
  String detActorNotFound(String name);

  /// No description provided for @detTmdbPitch.
  ///
  /// In en, this message translates to:
  /// **'Posters, synopses and cast. Quick setup by QR code from your phone.'**
  String get detTmdbPitch;

  /// No description provided for @detSaga.
  ///
  /// In en, this message translates to:
  /// **'Saga: {name}'**
  String detSaga(String name);

  /// No description provided for @detSameSaga.
  ///
  /// In en, this message translates to:
  /// **'Same saga'**
  String get detSameSaga;

  /// No description provided for @detSeasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get detSeasons;

  /// No description provided for @detSeasonsCountOne.
  ///
  /// In en, this message translates to:
  /// **'{seasons} season · {episodes} episodes'**
  String detSeasonsCountOne(int seasons, int episodes);

  /// No description provided for @detSeasonsCountMany.
  ///
  /// In en, this message translates to:
  /// **'{seasons} seasons · {episodes} episodes'**
  String detSeasonsCountMany(int seasons, int episodes);

  /// No description provided for @detLoadingEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Loading episodes…'**
  String get detLoadingEpisodes;

  /// No description provided for @detEpisodesError.
  ///
  /// In en, this message translates to:
  /// **'Episodes not loaded — {reason}.'**
  String detEpisodesError(String reason);

  /// No description provided for @detNoEpisodes.
  ///
  /// In en, this message translates to:
  /// **'No episode available for this series.'**
  String get detNoEpisodes;

  /// No description provided for @detSeasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String detSeasonNumber(String number);

  /// No description provided for @detEpisodesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} ep.'**
  String detEpisodesShort(int count);

  /// No description provided for @detRealOversold.
  ///
  /// In en, this message translates to:
  /// **'⚠ actual {definition}'**
  String detRealOversold(String definition);

  /// No description provided for @detReal.
  ///
  /// In en, this message translates to:
  /// **'actual {definition}'**
  String detReal(String definition);

  /// No description provided for @detResumeAt.
  ///
  /// In en, this message translates to:
  /// **'RESUME · {position}'**
  String detResumeAt(String position);

  /// No description provided for @detFavoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'⭐ “{title}” added to favorites'**
  String detFavoriteAdded(String title);

  /// No description provided for @detFavoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'🗑️ “{title}” removed from favorites'**
  String detFavoriteRemoved(String title);

  /// No description provided for @detNotInPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Not in your playlists — page shown from TMDB.'**
  String get detNotInPlaylists;

  /// No description provided for @detSearchInPlaylists.
  ///
  /// In en, this message translates to:
  /// **'SEARCH MY PLAYLISTS'**
  String get detSearchInPlaylists;

  /// No description provided for @detStatusReleased.
  ///
  /// In en, this message translates to:
  /// **'Released'**
  String get detStatusReleased;

  /// No description provided for @detStatusPostProduction.
  ///
  /// In en, this message translates to:
  /// **'Post-production'**
  String get detStatusPostProduction;

  /// No description provided for @detStatusInProduction.
  ///
  /// In en, this message translates to:
  /// **'In production'**
  String get detStatusInProduction;

  /// No description provided for @detStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get detStatusPlanned;

  /// No description provided for @detStatusReturning.
  ///
  /// In en, this message translates to:
  /// **'Returning'**
  String get detStatusReturning;

  /// No description provided for @detStatusEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get detStatusEnded;

  /// No description provided for @detStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get detStatusCanceled;

  /// No description provided for @sheetDetails.
  ///
  /// In en, this message translates to:
  /// **'Details & info'**
  String get sheetDetails;

  /// No description provided for @sheetReplayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Replay unavailable for this stream'**
  String get sheetReplayUnavailable;

  /// No description provided for @onbSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onbSkip;

  /// No description provided for @onbNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onbNext;

  /// No description provided for @onbStart.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onbStart;

  /// No description provided for @termPreviousErrors.
  ///
  /// In en, this message translates to:
  /// **'{count} PREVIOUS ERROR(S)'**
  String termPreviousErrors(int count);

  /// No description provided for @replayPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a moment to replay'**
  String get replayPickTitle;

  /// No description provided for @replayQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get replayQuality;

  /// No description provided for @replayDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get replayDay;

  /// No description provided for @replayOrManually.
  ///
  /// In en, this message translates to:
  /// **'OR CHOOSE MANUALLY'**
  String get replayOrManually;

  /// No description provided for @replayStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get replayStartTime;

  /// No description provided for @replayDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get replayDuration;

  /// No description provided for @replayAtWithDuration.
  ///
  /// In en, this message translates to:
  /// **'{day} at {time} ({duration})'**
  String replayAtWithDuration(String day, String time, String duration);

  /// No description provided for @replayNoEpg.
  ///
  /// In en, this message translates to:
  /// **'No EPG data available'**
  String get replayNoEpg;

  /// No description provided for @replayNoneTitle.
  ///
  /// In en, this message translates to:
  /// **'No replay available'**
  String get replayNoneTitle;

  /// No description provided for @replayNoneBody.
  ///
  /// In en, this message translates to:
  /// **'This channel exposes no Xtream EPG, or its timeshift is disabled. Try the manual picker from the TV action sheet.'**
  String get replayNoneBody;

  /// No description provided for @expExpiredSince.
  ///
  /// In en, this message translates to:
  /// **'Expired {days} days ago ({date})'**
  String expExpiredSince(int days, String date);

  /// No description provided for @expExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {days} days ({date})'**
  String expExpiresIn(int days, String date);

  /// No description provided for @expTitleExpired.
  ///
  /// In en, this message translates to:
  /// **'Playlist expired'**
  String get expTitleExpired;

  /// No description provided for @expTitleSoon.
  ///
  /// In en, this message translates to:
  /// **'Playlist expiring soon'**
  String get expTitleSoon;

  /// No description provided for @expBodyExpired.
  ///
  /// In en, this message translates to:
  /// **'This playlist can no longer be used. Renew with your provider to regain access.'**
  String get expBodyExpired;

  /// No description provided for @expBodySoon.
  ///
  /// In en, this message translates to:
  /// **'Renew with your provider so you do not lose access.'**
  String get expBodySoon;

  /// No description provided for @expLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get expLater;

  /// No description provided for @expSeeDetails.
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get expSeeDetails;

  /// No description provided for @memTitle.
  ///
  /// In en, this message translates to:
  /// **'MEMORY & STORAGE'**
  String get memTitle;

  /// No description provided for @memRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get memRefresh;

  /// No description provided for @memEntriesAndSize.
  ///
  /// In en, this message translates to:
  /// **'{count} entries · {size}'**
  String memEntriesAndSize(String count, String size);

  /// No description provided for @memOnDisk.
  ///
  /// In en, this message translates to:
  /// **'on disk · {count} entries · {size}'**
  String memOnDisk(String count, String size);

  /// No description provided for @memNoEntry.
  ///
  /// In en, this message translates to:
  /// **'0 entries · {size}'**
  String memNoEntry(String size);

  /// No description provided for @searchSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Search my playlists'**
  String get searchSheetTitle;

  /// No description provided for @searchSheetFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Title to search'**
  String get searchSheetFieldLabel;

  /// No description provided for @searchSheetOriginalTitle.
  ///
  /// In en, this message translates to:
  /// **'Original title: {title}'**
  String searchSheetOriginalTitle(String title);

  /// No description provided for @searchSheetTooShort.
  ///
  /// In en, this message translates to:
  /// **'Type at least 2 characters.'**
  String get searchSheetTooShort;

  /// No description provided for @searchSheetNoResult.
  ///
  /// In en, this message translates to:
  /// **'No title found in your playlists.'**
  String get searchSheetNoResult;

  /// No description provided for @nextEpPlayNow.
  ///
  /// In en, this message translates to:
  /// **'Play now  ·  {seconds}s'**
  String nextEpPlayNow(int seconds);

  /// No description provided for @aboutDiagnosticLog.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log'**
  String get aboutDiagnosticLog;

  /// No description provided for @aboutSourceOnGithub.
  ///
  /// In en, this message translates to:
  /// **'See the code on GitHub'**
  String get aboutSourceOnGithub;

  /// No description provided for @aboutAllReleases.
  ///
  /// In en, this message translates to:
  /// **'All releases'**
  String get aboutAllReleases;

  /// No description provided for @regionNoChange.
  ///
  /// In en, this message translates to:
  /// **'No change'**
  String get regionNoChange;

  /// No description provided for @regionShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get regionShowAll;

  /// No description provided for @regionHideAll.
  ///
  /// In en, this message translates to:
  /// **'Hide all'**
  String get regionHideAll;

  /// No description provided for @visualLangTitle.
  ///
  /// In en, this message translates to:
  /// **'Artwork language'**
  String get visualLangTitle;

  /// No description provided for @visualLangAuto.
  ///
  /// In en, this message translates to:
  /// **'Same as the device'**
  String get visualLangAuto;

  /// No description provided for @visualLangOriginalLabel.
  ///
  /// In en, this message translates to:
  /// **'Original version (no text)'**
  String get visualLangOriginalLabel;

  /// No description provided for @visualLangSubFr.
  ///
  /// In en, this message translates to:
  /// **'French posters and texts when they exist'**
  String get visualLangSubFr;

  /// No description provided for @visualLangSubEn.
  ///
  /// In en, this message translates to:
  /// **'English posters and texts'**
  String get visualLangSubEn;

  /// No description provided for @visualLangSubOriginal.
  ///
  /// In en, this message translates to:
  /// **'Poster without text when it exists, otherwise the original version'**
  String get visualLangSubOriginal;

  /// No description provided for @visualLangCurrently.
  ///
  /// In en, this message translates to:
  /// **'Currently: {tag}'**
  String visualLangCurrently(String tag);

  /// No description provided for @qualityHideVersions.
  ///
  /// In en, this message translates to:
  /// **'Hide the versions'**
  String get qualityHideVersions;

  /// No description provided for @qualityChangeVersion.
  ///
  /// In en, this message translates to:
  /// **'Change version'**
  String get qualityChangeVersion;

  /// No description provided for @navExitHint.
  ///
  /// In en, this message translates to:
  /// **'💡 To leave the app: press Back twice'**
  String get navExitHint;

  /// No description provided for @navExitConfirm.
  ///
  /// In en, this message translates to:
  /// **'Press Back again to leave'**
  String get navExitConfirm;

  /// No description provided for @settingsUsageReset.
  ///
  /// In en, this message translates to:
  /// **'🧹 Usage data reset'**
  String get settingsUsageReset;

  /// No description provided for @errUnexpected.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get errUnexpected;

  /// No description provided for @errUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get errUnknown;

  /// No description provided for @relayNothingReadable.
  ///
  /// In en, this message translates to:
  /// **'The conversion produced nothing playable.'**
  String get relayNothingReadable;

  /// No description provided for @healthNoStall.
  ///
  /// In en, this message translates to:
  /// **'no stall'**
  String get healthNoStall;

  /// No description provided for @reloadLessThanMinute.
  ///
  /// In en, this message translates to:
  /// **'less than a minute'**
  String get reloadLessThanMinute;

  /// No description provided for @plNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account selected. Please choose one in the settings.'**
  String get plNoActiveAccount;

  /// No description provided for @plNoActiveAccountShort.
  ///
  /// In en, this message translates to:
  /// **'No active account selected.'**
  String get plNoActiveAccountShort;

  /// No description provided for @plInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'The playlist URL for the account “{label}” is invalid. Check its configuration.'**
  String plInvalidUrl(String label);

  /// No description provided for @plEmptyFile.
  ///
  /// In en, this message translates to:
  /// **'The server returned an empty file. Check the playlist URL.'**
  String get plEmptyFile;

  /// No description provided for @bkFileTooShort.
  ///
  /// In en, this message translates to:
  /// **'Backup file too short or corrupted.'**
  String get bkFileTooShort;

  /// No description provided for @bkNotAnAetherFile.
  ///
  /// In en, this message translates to:
  /// **'This is not a valid .aether file.'**
  String get bkNotAnAetherFile;

  /// No description provided for @acctDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default account'**
  String get acctDefaultLabel;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @dlMediaStoreTimeout.
  ///
  /// In en, this message translates to:
  /// **'MediaStore did not answer'**
  String get dlMediaStoreTimeout;

  /// No description provided for @detRuntimePerEpisode.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m/episode'**
  String detRuntimePerEpisode(String minutes);

  /// No description provided for @detEpisodesBadSeriesId.
  ///
  /// In en, this message translates to:
  /// **'unreadable series identifier'**
  String get detEpisodesBadSeriesId;

  /// No description provided for @detEpisodesNoAccount.
  ///
  /// In en, this message translates to:
  /// **'account not found'**
  String get detEpisodesNoAccount;

  /// No description provided for @castOverlayResyncFull.
  ///
  /// In en, this message translates to:
  /// **'Resynchronize picture and sound'**
  String get castOverlayResyncFull;

  /// No description provided for @memSourceAndParsed.
  ///
  /// In en, this message translates to:
  /// **'source {source} · parsed {parsed}'**
  String memSourceAndParsed(String source, String parsed);

  /// No description provided for @expTodayOn.
  ///
  /// In en, this message translates to:
  /// **'Expires today ({date})'**
  String expTodayOn(String date);

  /// No description provided for @expTomorrowOn.
  ///
  /// In en, this message translates to:
  /// **'Expires tomorrow ({date})'**
  String expTomorrowOn(String date);

  /// No description provided for @catFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get catFavorites;

  /// No description provided for @catOthers.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOthers;

  /// No description provided for @catNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get catNew;

  /// No description provided for @catStaffPick.
  ///
  /// In en, this message translates to:
  /// **'Staff picks'**
  String get catStaffPick;

  /// No description provided for @catSelection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get catSelection;

  /// No description provided for @catCult.
  ///
  /// In en, this message translates to:
  /// **'Cult classics'**
  String get catCult;

  /// No description provided for @catBoxOffice.
  ///
  /// In en, this message translates to:
  /// **'Box office'**
  String get catBoxOffice;

  /// No description provided for @catOscar.
  ///
  /// In en, this message translates to:
  /// **'Oscars'**
  String get catOscar;

  /// No description provided for @catAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get catAction;

  /// No description provided for @catNews.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get catNews;

  /// No description provided for @catAnimation.
  ///
  /// In en, this message translates to:
  /// **'Animation'**
  String get catAnimation;

  /// No description provided for @catMartialArts.
  ///
  /// In en, this message translates to:
  /// **'Martial arts'**
  String get catMartialArts;

  /// No description provided for @catAdventure.
  ///
  /// In en, this message translates to:
  /// **'Adventure'**
  String get catAdventure;

  /// No description provided for @catBiopic.
  ///
  /// In en, this message translates to:
  /// **'Biopic'**
  String get catBiopic;

  /// No description provided for @catHeist.
  ///
  /// In en, this message translates to:
  /// **'Heist'**
  String get catHeist;

  /// No description provided for @catDisaster.
  ///
  /// In en, this message translates to:
  /// **'Disaster'**
  String get catDisaster;

  /// No description provided for @catComedy.
  ///
  /// In en, this message translates to:
  /// **'Comedy'**
  String get catComedy;

  /// No description provided for @catCrime.
  ///
  /// In en, this message translates to:
  /// **'Crime'**
  String get catCrime;

  /// No description provided for @catDance.
  ///
  /// In en, this message translates to:
  /// **'Dance'**
  String get catDance;

  /// No description provided for @catDocumentary.
  ///
  /// In en, this message translates to:
  /// **'Documentary'**
  String get catDocumentary;

  /// No description provided for @catDrama.
  ///
  /// In en, this message translates to:
  /// **'Drama'**
  String get catDrama;

  /// No description provided for @catSpy.
  ///
  /// In en, this message translates to:
  /// **'Spy'**
  String get catSpy;

  /// No description provided for @catFantasy.
  ///
  /// In en, this message translates to:
  /// **'Fantasy'**
  String get catFantasy;

  /// No description provided for @catHolidays.
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get catHolidays;

  /// No description provided for @catWar.
  ///
  /// In en, this message translates to:
  /// **'War'**
  String get catWar;

  /// No description provided for @catHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get catHistory;

  /// No description provided for @catHorror.
  ///
  /// In en, this message translates to:
  /// **'Horror'**
  String get catHorror;

  /// No description provided for @catKids.
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get catKids;

  /// No description provided for @catLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get catLegal;

  /// No description provided for @catKaraoke.
  ///
  /// In en, this message translates to:
  /// **'Karaoke'**
  String get catKaraoke;

  /// No description provided for @catMafia.
  ///
  /// In en, this message translates to:
  /// **'Mafia'**
  String get catMafia;

  /// No description provided for @catManga.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get catManga;

  /// No description provided for @catMaritime.
  ///
  /// In en, this message translates to:
  /// **'Maritime'**
  String get catMaritime;

  /// No description provided for @catMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get catMedical;

  /// No description provided for @catMedieval.
  ///
  /// In en, this message translates to:
  /// **'Medieval'**
  String get catMedieval;

  /// No description provided for @catMusical.
  ///
  /// In en, this message translates to:
  /// **'Musical'**
  String get catMusical;

  /// No description provided for @catPolice.
  ///
  /// In en, this message translates to:
  /// **'Crime drama'**
  String get catPolice;

  /// No description provided for @catPrison.
  ///
  /// In en, this message translates to:
  /// **'Prison'**
  String get catPrison;

  /// No description provided for @catRomance.
  ///
  /// In en, this message translates to:
  /// **'Romance'**
  String get catRomance;

  /// No description provided for @catSciFi.
  ///
  /// In en, this message translates to:
  /// **'Sci-Fi'**
  String get catSciFi;

  /// No description provided for @catStandUp.
  ///
  /// In en, this message translates to:
  /// **'Stand-up'**
  String get catStandUp;

  /// No description provided for @catSport.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get catSport;

  /// No description provided for @catSuperheroes.
  ///
  /// In en, this message translates to:
  /// **'Superheroes'**
  String get catSuperheroes;

  /// No description provided for @catSurvival.
  ///
  /// In en, this message translates to:
  /// **'Survival'**
  String get catSurvival;

  /// No description provided for @catTvMovie.
  ///
  /// In en, this message translates to:
  /// **'TV movie'**
  String get catTvMovie;

  /// No description provided for @catRealityTv.
  ///
  /// In en, this message translates to:
  /// **'Reality TV'**
  String get catRealityTv;

  /// No description provided for @catTalkShow.
  ///
  /// In en, this message translates to:
  /// **'Talk shows'**
  String get catTalkShow;

  /// No description provided for @catThriller.
  ///
  /// In en, this message translates to:
  /// **'Thriller'**
  String get catThriller;

  /// No description provided for @catSerialKiller.
  ///
  /// In en, this message translates to:
  /// **'Serial killer'**
  String get catSerialKiller;

  /// No description provided for @catRevenge.
  ///
  /// In en, this message translates to:
  /// **'Revenge'**
  String get catRevenge;

  /// No description provided for @catCars.
  ///
  /// In en, this message translates to:
  /// **'Cars'**
  String get catCars;

  /// No description provided for @catWestern.
  ///
  /// In en, this message translates to:
  /// **'Western'**
  String get catWestern;

  /// No description provided for @regFrance.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get regFrance;

  /// No description provided for @regAlbania.
  ///
  /// In en, this message translates to:
  /// **'Albania'**
  String get regAlbania;

  /// No description provided for @regAlgeria.
  ///
  /// In en, this message translates to:
  /// **'Algeria'**
  String get regAlgeria;

  /// No description provided for @regGermany.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get regGermany;

  /// No description provided for @regArmenia.
  ///
  /// In en, this message translates to:
  /// **'Armenia'**
  String get regArmenia;

  /// No description provided for @regAsia.
  ///
  /// In en, this message translates to:
  /// **'Asia'**
  String get regAsia;

  /// No description provided for @regBelgium.
  ///
  /// In en, this message translates to:
  /// **'Belgium'**
  String get regBelgium;

  /// No description provided for @regBosnia.
  ///
  /// In en, this message translates to:
  /// **'Bosnia'**
  String get regBosnia;

  /// No description provided for @regBrazil.
  ///
  /// In en, this message translates to:
  /// **'Brazil'**
  String get regBrazil;

  /// No description provided for @regCanada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get regCanada;

  /// No description provided for @regCroatia.
  ///
  /// In en, this message translates to:
  /// **'Croatia'**
  String get regCroatia;

  /// No description provided for @regSpain.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get regSpain;

  /// No description provided for @regGreece.
  ///
  /// In en, this message translates to:
  /// **'Greece'**
  String get regGreece;

  /// No description provided for @regIndian.
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get regIndian;

  /// No description provided for @regItaly.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get regItaly;

  /// No description provided for @regMaghreb.
  ///
  /// In en, this message translates to:
  /// **'Maghreb'**
  String get regMaghreb;

  /// No description provided for @regNetherlands.
  ///
  /// In en, this message translates to:
  /// **'Netherlands'**
  String get regNetherlands;

  /// No description provided for @regPoland.
  ///
  /// In en, this message translates to:
  /// **'Poland'**
  String get regPoland;

  /// No description provided for @regPortugal.
  ///
  /// In en, this message translates to:
  /// **'Portugal'**
  String get regPortugal;

  /// No description provided for @regRamadan.
  ///
  /// In en, this message translates to:
  /// **'Ramadan'**
  String get regRamadan;

  /// No description provided for @regRomania.
  ///
  /// In en, this message translates to:
  /// **'Romania'**
  String get regRomania;

  /// No description provided for @regRussia.
  ///
  /// In en, this message translates to:
  /// **'Russia'**
  String get regRussia;

  /// No description provided for @regScandinavia.
  ///
  /// In en, this message translates to:
  /// **'Scandinavia'**
  String get regScandinavia;

  /// No description provided for @regSwitzerland.
  ///
  /// In en, this message translates to:
  /// **'Switzerland'**
  String get regSwitzerland;

  /// No description provided for @regCzechia.
  ///
  /// In en, this message translates to:
  /// **'Czechia'**
  String get regCzechia;

  /// No description provided for @regExYugoslavia.
  ///
  /// In en, this message translates to:
  /// **'Former Yugoslavia'**
  String get regExYugoslavia;

  /// No description provided for @regDominicanRepublic.
  ///
  /// In en, this message translates to:
  /// **'Dominican Republic'**
  String get regDominicanRepublic;

  /// No description provided for @regOriginalNonFrench.
  ///
  /// In en, this message translates to:
  /// **'Original (non-French)'**
  String get regOriginalNonFrench;

  /// No description provided for @regLegendado.
  ///
  /// In en, this message translates to:
  /// **'Legendado (PT subtitles)'**
  String get regLegendado;

  /// No description provided for @acctChipMain.
  ///
  /// In en, this message translates to:
  /// **'MAIN'**
  String get acctChipMain;

  /// No description provided for @bootEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get bootEnterManually;

  /// No description provided for @bootConfigureWebConsole.
  ///
  /// In en, this message translates to:
  /// **'Set up via Web console'**
  String get bootConfigureWebConsole;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get searchPeople;

  /// No description provided for @personRoleDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get personRoleDirector;

  /// No description provided for @personRoleActor.
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get personRoleActor;

  /// No description provided for @personRoleWriter.
  ///
  /// In en, this message translates to:
  /// **'Writer'**
  String get personRoleWriter;

  /// No description provided for @personRoleProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get personRoleProduction;

  /// No description provided for @personRoleMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get personRoleMusic;

  /// No description provided for @personRoleCamera.
  ///
  /// In en, this message translates to:
  /// **'Cinematography'**
  String get personRoleCamera;

  /// No description provided for @optSpeedCurrentNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal (1.0×)'**
  String get optSpeedCurrentNormal;

  /// No description provided for @tracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get tracksTitle;

  /// No description provided for @tracksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'audio & subtitles'**
  String get tracksSubtitle;

  /// No description provided for @tracksAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get tracksAudio;

  /// No description provided for @tracksSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get tracksSubtitles;

  /// No description provided for @epgNow.
  ///
  /// In en, this message translates to:
  /// **'ON NOW'**
  String get epgNow;

  /// No description provided for @epgNext.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get epgNext;

  /// No description provided for @replayPrograms.
  ///
  /// In en, this message translates to:
  /// **'Programmes'**
  String get replayPrograms;

  /// No description provided for @replayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get replayToday;

  /// No description provided for @replayYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get replayYesterday;

  /// No description provided for @replayWatchLabel.
  ///
  /// In en, this message translates to:
  /// **'Watch  •  {label}'**
  String replayWatchLabel(String label);

  /// No description provided for @qualityWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch · {label}'**
  String qualityWatch(String label);

  /// No description provided for @actorBiography.
  ///
  /// In en, this message translates to:
  /// **'Biography'**
  String get actorBiography;

  /// No description provided for @actorBiographyMissing.
  ///
  /// In en, this message translates to:
  /// **'No biography available.'**
  String get actorBiographyMissing;

  /// No description provided for @actorAvailableBadge.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE'**
  String get actorAvailableBadge;

  /// No description provided for @detMainCast.
  ///
  /// In en, this message translates to:
  /// **'Main cast'**
  String get detMainCast;

  /// No description provided for @detSimilarAvailable.
  ///
  /// In en, this message translates to:
  /// **'Similar titles available'**
  String get detSimilarAvailable;

  /// No description provided for @detTrailerButton.
  ///
  /// In en, this message translates to:
  /// **'TRAILER'**
  String get detTrailerButton;

  /// No description provided for @themePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Movie Title'**
  String get themePreviewTitle;

  /// No description provided for @sheetReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get sheetReplay;

  /// No description provided for @sheetReplayDays.
  ///
  /// In en, this message translates to:
  /// **'Replay ({days}d)'**
  String sheetReplayDays(int days);

  /// No description provided for @memComputing.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get memComputing;

  /// No description provided for @memRamProcess.
  ///
  /// In en, this message translates to:
  /// **'Process RAM'**
  String get memRamProcess;

  /// No description provided for @memRamProcessValue.
  ///
  /// In en, this message translates to:
  /// **'{current} (peak {peak})'**
  String memRamProcessValue(String current, String peak);

  /// No description provided for @memImageCacheDisk.
  ///
  /// In en, this message translates to:
  /// **'Image cache (disk)'**
  String get memImageCacheDisk;

  /// No description provided for @memImageCacheRam.
  ///
  /// In en, this message translates to:
  /// **'Image cache (RAM)'**
  String get memImageCacheRam;

  /// No description provided for @memImageCacheRamValue.
  ///
  /// In en, this message translates to:
  /// **'{used} / {max} · {count} / {maxCount} img'**
  String memImageCacheRamValue(
    String used,
    String max,
    String count,
    String maxCount,
  );

  /// No description provided for @sizeBytes.
  ///
  /// In en, this message translates to:
  /// **'{n} B'**
  String sizeBytes(String n);

  /// No description provided for @sizeKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{n} kB'**
  String sizeKilobytes(String n);

  /// No description provided for @sizeMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{n} MB'**
  String sizeMegabytes(String n);

  /// No description provided for @sizeGigabytes.
  ///
  /// In en, this message translates to:
  /// **'{n} GB'**
  String sizeGigabytes(String n);

  /// No description provided for @dlActionRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get dlActionRestart;

  /// No description provided for @dlMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get dlMoreActions;

  /// No description provided for @playerQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get playerQuit;

  /// No description provided for @nextEpContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get nextEpContinue;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @statsAnnouncedLabel.
  ///
  /// In en, this message translates to:
  /// **'Declared'**
  String get statsAnnouncedLabel;

  /// No description provided for @replayGuideUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Guide unavailable'**
  String get replayGuideUnavailable;

  /// No description provided for @replayNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'not available'**
  String get replayNotAvailable;

  /// No description provided for @detEnableTmdb.
  ///
  /// In en, this message translates to:
  /// **'Turn on TMDB'**
  String get detEnableTmdb;

  /// No description provided for @dlRestartUpper.
  ///
  /// In en, this message translates to:
  /// **'RESTART'**
  String get dlRestartUpper;

  /// No description provided for @commonDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get commonDecrease;

  /// No description provided for @commonIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get commonIncrease;
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
    'that was used.',
  );
}
