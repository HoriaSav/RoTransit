// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navSearch => 'Search';

  @override
  String get navBus => 'Bus';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get city => 'City';

  @override
  String get notifications => 'Notifications';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get teTransport => 'TE transport';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRomanian => 'Romanian';

  @override
  String get languageGerman => 'German';

  @override
  String get offlineTimetables => 'Offline timetables';

  @override
  String offlineOnDevicePack(String version) {
    return 'On-device pack: $version';
  }

  @override
  String offlineServerMeta(String meta) {
    return 'Server meta (for updates): $meta';
  }

  @override
  String get offlineUpdatingBackground => 'Downloading timetables…';

  @override
  String offlineDownloadProgressPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String offlineDownloadEtaMinutes(int count) {
    return '~$count min left';
  }

  @override
  String offlineDownloadEtaSeconds(int count) {
    return '~$count sec left';
  }

  @override
  String offlineDownloadReceived(String size) {
    return 'Downloaded $size…';
  }

  @override
  String get offlineDownloadSaving => 'Saving timetables on device…';

  @override
  String offlineDownloadReceivedWithElapsed(String size, int seconds) {
    return 'Downloaded $size · $seconds sec';
  }

  @override
  String get offlinePackNotAvailablePreview => 'Not available in preview mode';

  @override
  String get offlinePackChooseCityFirst => 'Choose a city first';

  @override
  String get offlinePackNoneYet => 'Not downloaded';

  @override
  String get offlineMetaEndpointMissing =>
      'Not available — deploy GET /api/buses/offline-pack-meta on the server';

  @override
  String get timetableDownloadSourceBus => 'Bus timetables';

  @override
  String get timetableDownloadConfirmTitle => 'Download timetables?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Download offline bus timetables for $cityName? This may use mobile data.';
  }

  @override
  String get timetableDownloadAction => 'Download';

  @override
  String timetableDownloadSuccess(String cityName) {
    return 'Timetables downloaded for $cityName';
  }

  @override
  String get timetableDownloadFailed => 'Could not download timetables';

  @override
  String get timetableDownloadOffline =>
      'Connect to the internet to download timetables';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Timetables not downloaded';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Download bus timetables for this city in Settings to browse lines and schedules.';

  @override
  String get busTabOpenSettings => 'Go to Settings';

  @override
  String get version => 'Version';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfUse => 'Terms of use';

  @override
  String get help => 'Help';

  @override
  String get contactUs => 'Contact us';

  @override
  String countryLabel(String country) {
    return 'Country: $country';
  }

  @override
  String cityChangedTo(String name) {
    return 'City changed to $name';
  }

  @override
  String get cityUnavailable => 'Unavailable';

  @override
  String get pressBackAgainToExit => 'Press back again quickly to exit the app';
}
