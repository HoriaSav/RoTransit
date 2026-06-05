// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navSearch => 'Căutare';

  @override
  String get navBus => 'Autobuz';

  @override
  String get navFavorites => 'Favorite';

  @override
  String get navSettings => 'Setări';

  @override
  String get settingsTitle => 'Setări';

  @override
  String get city => 'Oraș';

  @override
  String get notifications => 'Notificări';

  @override
  String get darkMode => 'Mod întunecat';

  @override
  String get teTransport => 'Transport TE';

  @override
  String get language => 'Limbă';

  @override
  String get languageEnglish => 'Engleză';

  @override
  String get languageRomanian => 'Română';

  @override
  String get languageGerman => 'Germană';

  @override
  String get offlineTimetables => 'Orare offline';

  @override
  String offlineOnDevicePack(String version) {
    return 'Pachet pe dispozitiv: $version';
  }

  @override
  String offlineServerMeta(String meta) {
    return 'Meta server (actualizări): $meta';
  }

  @override
  String get offlineUpdatingBackground => 'Se descarcă orarele…';

  @override
  String offlineDownloadProgressPercent(int percent) {
    return 'Se descarcă… $percent%';
  }

  @override
  String offlineDownloadEtaMinutes(int count) {
    return '~$count min rămas';
  }

  @override
  String offlineDownloadEtaSeconds(int count) {
    return '~$count sec rămas';
  }

  @override
  String offlineDownloadReceived(String size) {
    return 'Descărcat $size…';
  }

  @override
  String get offlineDownloadSaving => 'Se salvează orarele pe dispozitiv…';

  @override
  String offlineDownloadReceivedWithElapsed(String size, int seconds) {
    return 'Descărcat $size · $seconds sec';
  }

  @override
  String get offlinePackNotAvailablePreview =>
      'Indisponibil în modul previzualizare';

  @override
  String get offlinePackChooseCityFirst => 'Alege mai întâi un oraș';

  @override
  String get offlinePackNoneYet => 'Nedescărcat';

  @override
  String get offlineMetaEndpointMissing =>
      'Indisponibil — implementează GET /api/buses/offline-pack-meta pe server';

  @override
  String get timetableDownloadSourceBus => 'Orare autobuz';

  @override
  String get timetableDownloadConfirmTitle => 'Descarci orarele?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Descarci orarele offline de autobuz pentru $cityName? Poate consuma date mobile.';
  }

  @override
  String get timetableDownloadAction => 'Descarcă';

  @override
  String timetableDownloadSuccess(String cityName) {
    return 'Orare descărcate pentru $cityName';
  }

  @override
  String get timetableDownloadFailed => 'Orarele nu au putut fi descărcate';

  @override
  String get timetableDownloadOffline =>
      'Conectează-te la internet pentru a descărca orarele';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Orare nedescărcate';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Descarcă orarele de autobuz pentru acest oraș din Setări ca să poți vedea liniile și programul.';

  @override
  String get busTabOpenSettings => 'Mergi la Setări';

  @override
  String get version => 'Versiune';

  @override
  String get privacyPolicy => 'Politica de confidențialitate';

  @override
  String get termsOfUse => 'Termeni de utilizare';

  @override
  String get help => 'Ajutor';

  @override
  String get contactUs => 'Contactează-ne';

  @override
  String countryLabel(String country) {
    return 'Țară: $country';
  }

  @override
  String cityChangedTo(String name) {
    return 'Oraș schimbat în $name';
  }

  @override
  String get cityUnavailable => 'Indisponibil';

  @override
  String get pressBackAgainToExit =>
      'Apasă din nou rapid pe Înapoi pentru a ieși din aplicație';
}
