// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navSearch => 'Suche';

  @override
  String get navBus => 'Bus';

  @override
  String get navFavorites => 'Favoriten';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get city => 'Stadt';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get darkMode => 'Dunkelmodus';

  @override
  String get teTransport => 'TE-Verkehr';

  @override
  String get language => 'Sprache';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageRomanian => 'Rumänisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get offlineTimetables => 'Offline-Fahrpläne';

  @override
  String offlineOnDevicePack(String version) {
    return 'Paket auf dem Gerät: $version';
  }

  @override
  String offlineServerMeta(String meta) {
    return 'Server-Meta (für Updates): $meta';
  }

  @override
  String get offlineUpdatingBackground => 'Fahrpläne werden heruntergeladen…';

  @override
  String offlineDownloadProgressPercent(int percent) {
    return 'Wird heruntergeladen… $percent%';
  }

  @override
  String offlineDownloadEtaMinutes(int count) {
    return 'noch ~$count Min.';
  }

  @override
  String offlineDownloadEtaSeconds(int count) {
    return 'noch ~$count Sek.';
  }

  @override
  String offlineDownloadReceived(String size) {
    return '$size heruntergeladen…';
  }

  @override
  String get offlineDownloadSaving =>
      'Fahrpläne werden auf dem Gerät gespeichert…';

  @override
  String offlineDownloadReceivedWithElapsed(String size, int seconds) {
    return '$size heruntergeladen · $seconds Sek.';
  }

  @override
  String get offlinePackNotAvailablePreview =>
      'Im Vorschaumodus nicht verfügbar';

  @override
  String get offlinePackChooseCityFirst => 'Wähle zuerst eine Stadt';

  @override
  String get offlinePackNoneYet => 'Nicht heruntergeladen';

  @override
  String get offlineMetaEndpointMissing =>
      'Nicht verfügbar — GET /api/buses/offline-pack-meta auf dem Server bereitstellen';

  @override
  String get timetableDownloadSourceBus => 'Busfahrpläne';

  @override
  String get timetableDownloadConfirmTitle => 'Fahrpläne herunterladen?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Offline-Busfahrpläne für $cityName herunterladen? Dies kann mobile Daten verbrauchen.';
  }

  @override
  String get timetableDownloadAction => 'Herunterladen';

  @override
  String timetableDownloadSuccess(String cityName) {
    return 'Fahrpläne für $cityName heruntergeladen';
  }

  @override
  String get timetableDownloadFailed =>
      'Fahrpläne konnten nicht heruntergeladen werden';

  @override
  String get timetableDownloadOffline =>
      'Verbinde dich mit dem Internet, um Fahrpläne herunterzuladen';

  @override
  String get busTabTimetablesNotDownloadedTitle =>
      'Fahrpläne nicht heruntergeladen';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Lade Busfahrpläne für diese Stadt in den Einstellungen herunter, um Linien und Fahrzeiten anzuzeigen.';

  @override
  String get busTabOpenSettings => 'Zu Einstellungen';

  @override
  String get version => 'Version';

  @override
  String get privacyPolicy => 'Datenschutz';

  @override
  String get termsOfUse => 'Nutzungsbedingungen';

  @override
  String get help => 'Hilfe';

  @override
  String get contactUs => 'Kontakt';

  @override
  String countryLabel(String country) {
    return 'Land: $country';
  }

  @override
  String cityChangedTo(String name) {
    return 'Stadt geändert zu $name';
  }

  @override
  String get cityUnavailable => 'Nicht verfügbar';

  @override
  String get pressBackAgainToExit =>
      'Drücke erneut schnell auf Zurück, um die App zu beenden';
}
