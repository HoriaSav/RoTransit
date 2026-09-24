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
  String get offlineTimetables => 'Offline-Fahrpläne';

  @override
  String get offlinePackWhatItCovers =>
      'Speichert Linien und Fahrpläne auf dem Telefon. Die Suche von A nach B braucht weiter Internet.';

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
  String get offlinePackChooseCityFirst => 'Wähle zuerst eine Stadt';

  @override
  String get offlinePackNoneYet => 'Nicht heruntergeladen';

  @override
  String get offlinePackAvailableOnDevice => 'Auf dem Gerät verfügbar';

  @override
  String offlinePackDownloaded(String date) {
    return 'Heruntergeladen $date';
  }

  @override
  String offlinePackDownloadedWithWeek(String date, String week) {
    return 'Heruntergeladen $date · Woche $week';
  }

  @override
  String get offlineMetaEndpointMissing =>
      'Nicht verfügbar — GET /api/buses/offline-pack-meta auf dem Server bereitstellen';

  @override
  String get timetableDownloadSourceBus => 'Busfahrpläne';

  @override
  String get timetableDownloadConfirmTitle => 'Fahrpläne herunterladen?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Linien und Fahrpläne für $cityName auf dieses Telefon herunterladen? Die Suche von A nach B braucht weiter Internet. Dies kann mobile Daten verbrauchen.';
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
  String get timetableDownloadAlreadyUpToDate =>
      'Fahrpläne sind bereits heruntergeladen und aktuell';

  @override
  String get busTabTimetablesNotDownloadedTitle =>
      'Fahrpläne nicht heruntergeladen';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Lade Busfahrpläne für diese Stadt in den Einstellungen herunter, um Linien und Fahrzeiten anzuzeigen.';

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
  String busFrom(String destination) {
    return 'Von: $destination';
  }

  @override
  String busLineTitle(String short, String long) {
    return 'Bus $short · $long';
  }

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

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonBack => 'Zurück';

  @override
  String get openSettings => 'Einstellungen';

  @override
  String get errorCompleteSearchFields =>
      'Bitte Von, Nach, Datum und Uhrzeit ausfüllen.';

  @override
  String get errorSelectStationsFromPicker =>
      'Wähle beide Haltestellen aus der Liste oder der Karte.';

  @override
  String get errorCityContextUnavailable =>
      'Stadt konnte nicht geladen werden. Bitte erneut versuchen.';

  @override
  String get errorSearchRequiresInternet =>
      'Routensuche benötigt eine Internetverbindung.';

  @override
  String get errorNoRoutesFound => 'Keine Routen für diese Fahrt gefunden.';

  @override
  String get errorServerUnreachable =>
      'Server nicht erreichbar. Verbindung prüfen und erneut versuchen.';

  @override
  String get errorServerTimeout =>
      'Der Server hat zu lange gebraucht. Bitte erneut versuchen.';

  @override
  String get errorRoutingUnavailable =>
      'Routenplanung ist vorübergehend nicht verfügbar.';

  @override
  String get errorInvalidSearchParams =>
      'Haltestellen, Datum und Uhrzeit prüfen.';

  @override
  String get errorCityNotFound => 'Diese Stadt ist noch nicht verfügbar.';

  @override
  String get errorUnexpectedError =>
      'Etwas ist schiefgelaufen. Bitte erneut versuchen.';

  @override
  String get errorRouteShapeSimplified =>
      'Vollständige Routendetails konnten nicht geladen werden. Vereinfachte Ansicht.';

  @override
  String get errorLoadMoreRoutesFailed =>
      'Weitere Routen konnten nicht geladen werden. Erneut versuchen.';

  @override
  String get successAddedToFavorites => 'Zu Favoriten hinzugefügt';

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
  String get searchFrom => 'Von';

  @override
  String get searchTo => 'Nach';

  @override
  String get searchDate => 'Datum';

  @override
  String get searchTime => 'Uhrzeit';

  @override
  String get searchButton => 'Suchen';

  @override
  String get searchRecent => 'Zuletzt';

  @override
  String get searchNoRecent => 'Noch keine letzten Suchen.';

  @override
  String get searchCouldNotLoadRecent =>
      'Letzte Suchen konnten nicht geladen werden.';

  @override
  String get searchSelectDate => 'Datum wählen';

  @override
  String get searchSelectTime => 'Uhrzeit wählen';

  @override
  String get searchSwapTooltip => 'Von und Nach tauschen';

  @override
  String get searchDeparture => 'Abfahrt';

  @override
  String get searchDestination => 'Ziel';

  @override
  String get searchSelectStop => 'Haltestelle wählen';

  @override
  String get searchStationHint => 'Haltestelle suchen';

  @override
  String get searchCurrentLocation => 'Aktueller Standort';

  @override
  String get searchSelectOnMap => 'Auf Karte wählen';

  @override
  String get searchNoNearbyStops =>
      'Keine Haltestellen in der Nähe. Oben suchen oder Auf Karte wählen.';

  @override
  String get searchNoMatches =>
      'Keine Treffer. Anderen Begriff versuchen oder Auf Karte wählen.';

  @override
  String get searchEnableLocationForDistance =>
      'Standort für Entfernung aktivieren';

  @override
  String get searchWaitingForGps => 'Warte auf GPS...';

  @override
  String get searchUsingGps => 'GPS-Position wird verwendet';

  @override
  String get searchTapToRetryLocation =>
      'Tippen zum Wiederholen — genauen Standort aktivieren';

  @override
  String get searchGettingLocation => 'Standort wird ermittelt...';

  @override
  String get origin => 'Start';

  @override
  String get destination => 'Ziel';

  @override
  String get favoritesSavedJourneys => 'Gespeicherte Fahrten';

  @override
  String get favoritesEmptyTitle => 'Noch keine gespeicherten Fahrten';

  @override
  String get favoritesEmptyBody =>
      'Suche eine Route, öffne Details und tippe Zu Favoriten hinzufügen.';

  @override
  String get favoritesDeleteTitle => 'Fahrt löschen?';

  @override
  String get favoritesDeleteBody => 'Diese Fahrt aus den Favoriten entfernen?';

  @override
  String get favoritesCouldNotLoad =>
      'Gespeicherte Fahrten konnten nicht geladen werden';

  @override
  String get favoritesDirect => 'Direkt';

  @override
  String favoritesTransfers(int count) {
    return '$count Umstiege';
  }

  @override
  String get favoritesOneTransfer => '1 Umstieg';

  @override
  String get savedJourneyLabel => 'Gespeicherte Fahrt';

  @override
  String get mapWalkingRoute => 'Fußweg';

  @override
  String get mapRotateNorth => 'Karte nach Norden ausrichten';

  @override
  String get mapSearchRoutesHint => 'Routen suchen, um Optionen hier zu sehen.';

  @override
  String get mapLoading => 'Wird geladen…';

  @override
  String mapLoadMoreTripsWithRemaining(int count, int remaining) {
    return '$count weitere Fahrten laden ($remaining übrig)';
  }

  @override
  String mapLoadMoreTrips(int count, String tripWord) {
    return '$count weitere $tripWord laden';
  }

  @override
  String mapLoadNextTrips(int count) {
    return 'Nächste $count Fahrten laden';
  }

  @override
  String get mapTripSingular => 'Fahrt';

  @override
  String get mapTripPlural => 'Fahrten';

  @override
  String get mapNoTransfers => 'Keine Umstiege';

  @override
  String mapTransfers(int count) {
    return '$count Umstiege';
  }

  @override
  String get mapOneTransfer => '1 Umstieg';

  @override
  String get mapAddToFavorites => 'Zu Favoriten hinzufügen';

  @override
  String get mapSteps => 'Schritte';

  @override
  String mapPriceLei(int price) {
    return '$price lei';
  }

  @override
  String mapTransfersAndPrice(String transfers, String price) {
    return '$transfers • $price';
  }

  @override
  String get transitBus => 'Bus';

  @override
  String get transitTrolleybus => 'Oberleitungsbus';

  @override
  String get transitTram => 'Straßenbahn';

  @override
  String get transitTrain => 'Zug';

  @override
  String get transitMetro => 'U-Bahn';

  @override
  String get transitWalk => 'Zu Fuß';

  @override
  String get transitGeneric => 'ÖPNV';
}
