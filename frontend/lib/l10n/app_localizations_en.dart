import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RoTransit';

  @override
  String get navMap => 'Map';

  @override
  String get navBus => 'Timetable';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get city => 'City';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get teTransport => 'TE transport';

  @override
  String get teTransportSubtitle => 'Student transport';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRomanian => 'Romanian';

  @override
  String get languageGerman => 'German';

  @override
  String get settingsDataAsOf => 'Brașov data as of';

  @override
  String get settingsFaresTitle => 'Fares & tickets';

  @override
  String get settingsFaresSubtitle => 'Urban vs metropolitan · where to buy';

  @override
  String get faresSheetTitle => 'RATBV fares (static guide)';

  @override
  String get faresSheetBody =>
      'Urban (inside Brașov): about 5 RON per ride on the standard ticket (confirm on ratbv.ro — prices change).\n\nMetropolitan / zone tickets: higher fares for trips into nearby communes (roughly 7–12 RON depending on zone in the GTFS fare table).\n\nBuy tickets: 24pay app, RATBV ticket machines/kiosks, and other channels listed on the operator site. This app does not sell tickets.';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Timetables not available';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Timetables are available only for Brașov for now. Choose Brașov in Settings.';

  @override
  String get busTabOpenSettings => 'Go to Settings';

  @override
  String get busTabUrban => 'Urban';

  @override
  String get busTabRural => 'Rural';

  @override
  String get busTabTe => 'TE';

  @override
  String get busNoLinesFound => 'No bus lines found.';

  @override
  String get busCouldNotLoadLines => 'Could not load bus lines';

  @override
  String get busNoLinesInGroup => 'No lines in this group.';

  @override
  String get busRouteFallback => 'Bus route';

  @override
  String busLineFallback(String number) {
    return 'Bus $number';
  }

  @override
  String get busBack => 'Back';

  @override
  String get busReverseDirection => 'Reverse direction';

  @override
  String get busNoStopsFound => 'No stops found.';

  @override
  String get busCouldNotLoadStops => 'Could not load route stops';

  @override
  String get busCouldNotLoadTimetable => 'Could not load timetable';

  @override
  String get busNoDepartures => 'No departures for this stop.';

  @override
  String busTowards(String destination) {
    return 'Towards: $destination';
  }

  @override
  String get favoriteLineAdd => 'Favorite line';

  @override
  String get timetableHour => 'Hour';

  @override
  String get timetableWeekdays => 'Mon-Fri';

  @override
  String get timetableSaturday => 'Sat';

  @override
  String get timetableSunday => 'Sun';

  @override
  String get version => 'Version';

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

  @override
  String get openSettings => 'Settings';

  @override
  String get linkOpenFailed => 'Could not open the link';

  @override
  String get errorServerUnreachable =>
      'Cannot reach the server. Check your connection and try again.';

  @override
  String get errorServerTimeout =>
      'The server took too long to respond. Try again.';

  @override
  String get errorUnexpectedError => 'Something went wrong. Please try again.';

  @override
  String get locationServicesOff =>
      'Location services are turned off on this device.';

  @override
  String get locationPermissionBlocked =>
      'Location permission is blocked. Open Settings to allow precise location.';

  @override
  String get locationPermissionDenied => 'Location permission was denied.';

  @override
  String get locationPreciseRequired =>
      'Enable Precise Location in Settings for accurate stop distances.';

  @override
  String get locationGpsFailed =>
      'Could not get a reliable GPS fix. Try outdoors, enable precise location, or use Select on map.';

  @override
  String get searchSelectStop => 'Select stop';

  @override
  String get favoritesCouldNotLoad => 'Could not load favorites';

  @override
  String get favoritesCouldNotSave => 'Could not save favorite';

  @override
  String get favoritesStopsTitle => 'Stops';

  @override
  String get favoritesStopsEmpty =>
      'No favorite stops yet. Open a stop on the map and tap the star.';

  @override
  String get favoritesLinesTitle => 'Lines';

  @override
  String get favoritesLinesEmpty =>
      'No favorite lines yet. In Timetable, tap the star next to a line.';

  @override
  String get favoriteStopAdd => 'Favorite stop';

  @override
  String get favoriteRemove => 'Remove favorite';

  @override
  String get mapRotateNorth => 'Rotate map to north';

  @override
  String get mapSearchStationsHint => 'Search Brașov stations';

  @override
  String get mapScheduleNotLive => 'Schedule times · not live GPS';

  @override
  String stopBoardWindow(int minutes) {
    return 'Next $minutes min';
  }

  @override
  String get stopBoardCouldNotLoad => 'Could not load schedule';

  @override
  String stopBoardEmpty(int minutes) {
    return 'No departures in the next $minutes minutes';
  }

  @override
  String stopBoardShowMore(int minutes) {
    return 'Show next $minutes minutes';
  }

  @override
  String stopBoardUntil(String time) {
    return 'Until $time';
  }

  @override
  String stopBoardEmptyUntil(String time) {
    return 'No departures until $time';
  }

  @override
  String stopBoardFeedEnded(String date) {
    return 'Timetable data ended on $date. Update the app to see departures.';
  }

  @override
  String get stopOpenInGoogleMaps => 'Open in Google Maps';

  @override
  String get busSearchLineHint => 'Search line number or name';
}
