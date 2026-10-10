import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navMap => 'Karte';

  @override
  String get navBus => 'Fahrplan';

  @override
  String get navFavorites => 'Favoriten';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get city => 'Stadt';

  @override
  String get darkMode => 'Dunkelmodus';

  @override
  String get teTransport => 'TE-Verkehr';

  @override
  String get teTransportSubtitle => 'Schülerverkehr';

  @override
  String get language => 'Sprache';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageRomanian => 'Rumänisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get settingsDataAsOf => 'Brașov-Daten vom';

  @override
  String get settingsFaresTitle => 'Tarife & Tickets';

  @override
  String get settingsFaresSubtitle => 'Stadt vs. Umland · wo kaufen';

  @override
  String get faresSheetTitle => 'RATBV-Tarife (statische Übersicht)';

  @override
  String get faresSheetBody =>
      'Stadt (innerhalb Brașov): etwa 5 RON pro Fahrt mit dem Standardticket (auf ratbv.ro prüfen — Preise ändern sich).\n\nUmland- / Zonentickets: höhere Preise für Fahrten in Nachbargemeinden (etwa 7–12 RON je nach Zone laut GTFS-Tariftabelle).\n\nTickets kaufen: 24pay-App, RATBV-Automaten/Kioske und weitere Kanäle auf der Website des Betreibers. Diese App verkauft keine Tickets.';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Fahrpläne nicht verfügbar';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Fahrpläne gibt es vorerst nur für Brașov. Wähle Brașov in den Einstellungen.';

  @override
  String get busTabOpenSettings => 'Zu Einstellungen';

  @override
  String get busTabUrban => 'Stadt';

  @override
  String get busTabRural => 'Land';

  @override
  String get busTabTe => 'TE';

  @override
  String get busNoLinesFound => 'Keine Buslinien gefunden.';

  @override
  String get busCouldNotLoadLines => 'Buslinien konnten nicht geladen werden';

  @override
  String get busNoLinesInGroup => 'Keine Linien in dieser Gruppe.';

  @override
  String get busRouteFallback => 'Buslinie';

  @override
  String busLineFallback(String number) {
    return 'Bus $number';
  }

  @override
  String get busBack => 'Zurück';

  @override
  String get busReverseDirection => 'Richtung umkehren';

  @override
  String get busNoStopsFound => 'Keine Haltestellen gefunden.';

  @override
  String get busCouldNotLoadStops =>
      'Haltestellen konnten nicht geladen werden';

  @override
  String get busCouldNotLoadTimetable => 'Fahrplan konnte nicht geladen werden';

  @override
  String get busNoDepartures => 'Keine Abfahrten an dieser Haltestelle.';

  @override
  String busTowards(String destination) {
    return 'Richtung: $destination';
  }

  @override
  String get favoriteLineAdd => 'Linie merken';

  @override
  String get timetableHour => 'Stunde';

  @override
  String get timetableWeekdays => 'Mo-Fr';

  @override
  String get timetableSaturday => 'Sa';

  @override
  String get timetableSunday => 'So';

  @override
  String get version => 'Version';

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

  @override
  String get openSettings => 'Einstellungen';

  @override
  String get linkOpenFailed => 'Link konnte nicht geöffnet werden';

  @override
  String get errorServerUnreachable =>
      'Server nicht erreichbar. Verbindung prüfen und erneut versuchen.';

  @override
  String get errorServerTimeout =>
      'Der Server hat zu lange gebraucht. Bitte erneut versuchen.';

  @override
  String get errorUnexpectedError =>
      'Etwas ist schiefgelaufen. Bitte erneut versuchen.';

  @override
  String get locationServicesOff =>
      'Standortdienste sind auf diesem Gerät deaktiviert.';

  @override
  String get locationPermissionBlocked =>
      'Standortberechtigung blockiert. Einstellungen öffnen für genauen Standort.';

  @override
  String get locationPermissionDenied =>
      'Standortberechtigung wurde verweigert.';

  @override
  String get locationPreciseRequired =>
      'Aktiviere Genauen Standort in den Einstellungen für korrekte Entfernungen.';

  @override
  String get locationGpsFailed =>
      'Kein zuverlässiger GPS-Fix. Draußen versuchen oder Auf Karte wählen.';

  @override
  String get searchSelectStop => 'Haltestelle wählen';

  @override
  String get favoritesCouldNotLoad => 'Favoriten konnten nicht geladen werden';

  @override
  String get favoritesCouldNotSave => 'Favorit konnte nicht gespeichert werden';

  @override
  String get favoritesStopsTitle => 'Haltestellen';

  @override
  String get favoritesStopsEmpty =>
      'Noch keine Lieblingshaltestellen. Öffne eine Haltestelle auf der Karte und tippe auf den Stern.';

  @override
  String get favoritesLinesTitle => 'Linien';

  @override
  String get favoritesLinesEmpty =>
      'Noch keine Lieblingslinien. Tippe im Fahrplan auf den Stern neben einer Linie.';

  @override
  String get favoriteStopAdd => 'Haltestelle merken';

  @override
  String get favoriteRemove => 'Aus Favoriten entfernen';

  @override
  String get mapRotateNorth => 'Karte nach Norden ausrichten';

  @override
  String get mapSearchStationsHint => 'Haltestellen in Brașov suchen';

  @override
  String get mapScheduleNotLive => 'Fahrplanzeiten · kein Live-GPS';

  @override
  String stopBoardWindow(int minutes) {
    return 'Nächste $minutes Min.';
  }

  @override
  String get stopBoardCouldNotLoad => 'Fahrplan konnte nicht geladen werden';

  @override
  String stopBoardEmpty(int minutes) {
    return 'Keine Abfahrten in den nächsten $minutes Minuten';
  }

  @override
  String stopBoardShowMore(int minutes) {
    return 'Nächste $minutes Minuten anzeigen';
  }

  @override
  String stopBoardUntil(String time) {
    return 'Bis $time';
  }

  @override
  String stopBoardEmptyUntil(String time) {
    return 'Keine Abfahrten bis $time';
  }

  @override
  String stopBoardFeedEnded(String date) {
    return 'Die Fahrplandaten endeten am $date. Aktualisiere die App, um Abfahrten zu sehen.';
  }

  @override
  String get stopOpenInGoogleMaps => 'In Google Maps öffnen';

  @override
  String get busSearchLineHint => 'Linie nach Nummer oder Name suchen';
}
