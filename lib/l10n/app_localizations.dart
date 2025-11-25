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

  /// No description provided for @searchPageDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'AetherStream'**
  String get searchPageDefaultTitle;

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

  /// No description provided for @playlistManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlist Download'**
  String get playlistManagementTitle;

  /// No description provided for @playlistCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlist .m3u'**
  String get playlistCardTitle;

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

  /// No description provided for @playlistInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlist Info'**
  String get playlistInfoTitle;

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
