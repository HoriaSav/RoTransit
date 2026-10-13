import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navMap => 'Hartă';

  @override
  String get navBus => 'Program';

  @override
  String get navFavorites => 'Favorite';

  @override
  String get settingsTitle => 'Setări';

  @override
  String get city => 'Oraș';

  @override
  String get darkMode => 'Mod întunecat';

  @override
  String get teTransport => 'Transport TE';

  @override
  String get teTransportSubtitle => 'Transport elevi';

  @override
  String get language => 'Limbă';

  @override
  String get languageEnglish => 'Engleză';

  @override
  String get languageRomanian => 'Română';

  @override
  String get languageGerman => 'Germană';

  @override
  String get settingsDataAsOf => 'Date Brașov valabile din';

  @override
  String get settingsFaresTitle => 'Tarife și bilete';

  @override
  String get settingsFaresSubtitle =>
      'Urban vs. metropolitan · de unde cumperi';

  @override
  String get faresSheetTitle => 'Tarife RATBV (ghid static)';

  @override
  String get faresSheetBody =>
      'Urban (în Brașov): aproximativ 5 lei pe călătorie cu biletul standard (verifică pe ratbv.ro — prețurile se schimbă).\n\nBilete metropolitane / pe zone: tarife mai mari pentru comunele din apropiere (cam 7–12 lei, în funcție de zonă, conform tabelului de tarife GTFS).\n\nCumpără bilete: aplicația 24pay, automatele/chioșcurile RATBV și alte canale listate pe site-ul operatorului. Aplicația nu vinde bilete.';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Orare indisponibile';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Deocamdată orarele sunt disponibile doar pentru Brașov. Alege Brașov din Setări.';

  @override
  String get busTabOpenSettings => 'Mergi la Setări';

  @override
  String get busTabUrban => 'Urban';

  @override
  String get busTabRural => 'Rural';

  @override
  String get busTabTe => 'TE';

  @override
  String get busNoLinesFound => 'Nu s-au găsit linii de autobuz.';

  @override
  String get busCouldNotLoadLines => 'Nu s-au putut încărca liniile';

  @override
  String get busNoLinesInGroup => 'Nicio linie în acest grup.';

  @override
  String get busRouteFallback => 'Linie de autobuz';

  @override
  String busLineFallback(String number) {
    return 'Autobuz $number';
  }

  @override
  String get busBack => 'Înapoi';

  @override
  String get busReverseDirection => 'Inversează direcția';

  @override
  String get busNoStopsFound => 'Nu s-au găsit stații.';

  @override
  String get busCouldNotLoadStops => 'Nu s-au putut încărca stațiile';

  @override
  String get busCouldNotLoadTimetable => 'Nu s-a putut încărca orarul';

  @override
  String get busNoDepartures => 'Nicio plecare la această stație.';

  @override
  String busTowards(String destination) {
    return 'Spre: $destination';
  }

  @override
  String get favoriteLineAdd => 'Adaugă linia la favorite';

  @override
  String get timetableHour => 'Oră';

  @override
  String get timetableWeekdays => 'L-V';

  @override
  String get timetableSaturday => 'Sâm';

  @override
  String get timetableSunday => 'Dum';

  @override
  String get version => 'Versiune';

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

  @override
  String get openSettings => 'Setări';

  @override
  String get linkOpenFailed => 'Linkul nu a putut fi deschis';

  @override
  String get errorServerUnreachable =>
      'Serverul nu poate fi contactat. Verifică conexiunea și încearcă din nou.';

  @override
  String get errorServerTimeout =>
      'Serverul a răspuns prea greu. Încearcă din nou.';

  @override
  String get errorUnexpectedError => 'Ceva nu a funcționat. Încearcă din nou.';

  @override
  String get locationServicesOff =>
      'Serviciile de locație sunt dezactivate pe acest dispozitiv.';

  @override
  String get locationPermissionBlocked =>
      'Permisiunea de locație este blocată. Deschide Setările pentru locație precisă.';

  @override
  String get locationPermissionDenied =>
      'Permisiunea de locație a fost refuzată.';

  @override
  String get locationPreciseRequired =>
      'Activează Locația precisă în Setări pentru distanțe corecte.';

  @override
  String get locationGpsFailed =>
      'Nu s-a putut obține o poziție GPS fiabilă. Încearcă în aer liber sau folosește Selectează pe hartă.';

  @override
  String get searchSelectStop => 'Selectează stația';

  @override
  String get favoritesCouldNotLoad => 'Nu s-au putut încărca favoritele';

  @override
  String get favoritesCouldNotSave => 'Nu s-a putut salva favoritul';

  @override
  String get favoritesStopsTitle => 'Stații';

  @override
  String get favoritesStopsEmpty =>
      'Nicio stație favorită încă. Deschide o stație pe hartă și apasă steaua.';

  @override
  String get favoritesLinesTitle => 'Linii';

  @override
  String get favoritesLinesEmpty =>
      'Nicio linie favorită încă. În Program, apasă steaua de lângă o linie.';

  @override
  String get favoriteStopAdd => 'Adaugă stația la favorite';

  @override
  String get favoriteRemove => 'Elimină din favorite';

  @override
  String get mapRotateNorth => 'Orientează harta spre nord';

  @override
  String get mapSearchStationsHint => 'Caută stații în Brașov';

  @override
  String get mapScheduleNotLive => 'Ore din orar · nu GPS live';

  @override
  String stopBoardWindow(int minutes) {
    return 'Următoarele $minutes min';
  }

  @override
  String get stopBoardCouldNotLoad => 'Programul nu a putut fi încărcat';

  @override
  String stopBoardEmpty(int minutes) {
    return 'Nicio plecare în următoarele $minutes minute';
  }

  @override
  String stopBoardShowMore(int minutes) {
    return 'Arată următoarele $minutes minute';
  }

  @override
  String stopBoardUntil(String time) {
    return 'Până la $time';
  }

  @override
  String stopBoardEmptyUntil(String time) {
    return 'Nicio plecare până la $time';
  }

  @override
  String stopBoardFeedEnded(String date) {
    return 'Datele din orar s-au încheiat pe $date. Actualizează aplicația pentru a vedea plecările.';
  }

  @override
  String get stopOpenInGoogleMaps => 'Deschide în Google Maps';

  @override
  String get busSearchLineHint => 'Caută număr sau nume linie';
}
