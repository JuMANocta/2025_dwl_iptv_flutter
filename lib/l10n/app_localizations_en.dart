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
  String get searchPageDefaultTitle => 'AetherStream';

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
  String get playlistManagementTitle => 'Playlist Download';

  @override
  String get playlistCardTitle => 'Playlist .m3u';

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
  String get playlistInfoTitle => 'Playlist Info';

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
}
