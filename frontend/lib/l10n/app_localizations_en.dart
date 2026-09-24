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
  String get offlineTimetables => 'Offline timetables';

  @override
  String get offlinePackWhatItCovers =>
      'Stores bus lines and stop timetables on the phone. Searching a trip from A to B still needs internet.';

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
  String get offlinePackChooseCityFirst => 'Choose a city first';

  @override
  String get offlinePackNoneYet => 'Not downloaded';

  @override
  String get offlinePackAvailableOnDevice => 'Available on device';

  @override
  String offlinePackDownloaded(String date) {
    return 'Downloaded $date';
  }

  @override
  String offlinePackDownloadedWithWeek(String date, String week) {
    return 'Downloaded $date · week $week';
  }

  @override
  String get offlineMetaEndpointMissing =>
      'Not available — deploy GET /api/buses/offline-pack-meta on the server';

  @override
  String get timetableDownloadSourceBus => 'Bus timetables';

  @override
  String get timetableDownloadConfirmTitle => 'Download timetables?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Download bus lines and stop timetables for $cityName onto this phone? Searching a trip from A to B still needs internet. This may use mobile data.';
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
  String get timetableDownloadAlreadyUpToDate =>
      'Timetables are already downloaded and up to date';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Timetables not downloaded';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Download bus timetables for this city in Settings to browse lines and schedules.';

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
  String get busSearchLineHint => 'Search line number or name';

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
  String busFrom(String destination) {
    return 'From: $destination';
  }

  @override
  String busLineTitle(String short, String long) {
    return 'Bus $short · $long';
  }

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

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonBack => 'Back';

  @override
  String get openSettings => 'Settings';

  @override
  String get errorCompleteSearchFields =>
      'Please fill in From, To, date, and time.';

  @override
  String get errorSelectStationsFromPicker =>
      'Select both stations from the list or map.';

  @override
  String get errorCityContextUnavailable =>
      'Could not load your city. Try again later.';

  @override
  String get errorSearchRequiresInternet =>
      'Route search needs an internet connection.';

  @override
  String get errorNoRoutesFound => 'No routes found for this trip.';

  @override
  String get errorServerUnreachable =>
      'Cannot reach the server. Check your connection and try again.';

  @override
  String get errorServerTimeout =>
      'The server took too long to respond. Try again.';

  @override
  String get errorRoutingUnavailable =>
      'Trip planning is temporarily unavailable.';

  @override
  String get errorInvalidSearchParams => 'Check your stations, date, and time.';

  @override
  String get errorCityNotFound => 'This city is not available yet.';

  @override
  String get errorUnexpectedError => 'Something went wrong. Please try again.';

  @override
  String get errorRouteShapeSimplified =>
      'Could not load full route details. Showing a simplified view.';

  @override
  String get errorLoadMoreRoutesFailed =>
      'Could not load more routes. Try again.';

  @override
  String get successAddedToFavorites => 'Added to favorites';

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
  String get searchFrom => 'From';

  @override
  String get searchTo => 'To';

  @override
  String get searchDate => 'Date';

  @override
  String get searchTime => 'Time';

  @override
  String get searchButton => 'Search';

  @override
  String get searchRecent => 'Recent';

  @override
  String get searchNoRecent => 'No recent searches yet.';

  @override
  String get searchCouldNotLoadRecent => 'Could not load recent searches.';

  @override
  String get searchSelectDate => 'Select date';

  @override
  String get searchSelectTime => 'Select time';

  @override
  String get searchSwapTooltip => 'Swap From and To';

  @override
  String get searchDeparture => 'Departure';

  @override
  String get searchDestination => 'Destination';

  @override
  String get searchSelectStop => 'Select stop';

  @override
  String get searchStationHint => 'Search station';

  @override
  String get searchCurrentLocation => 'Current location';

  @override
  String get searchSelectOnMap => 'Select on map';

  @override
  String get searchNoNearbyStops =>
      'No nearby stops. Search above or use Select on map.';

  @override
  String get searchNoMatches =>
      'No matches for your search. Try another query or Select on map.';

  @override
  String get searchEnableLocationForDistance => 'Enable location for distance';

  @override
  String get searchWaitingForGps => 'Waiting for GPS...';

  @override
  String get searchUsingGps => 'Using your GPS position';

  @override
  String get searchTapToRetryLocation =>
      'Tap to retry — enable precise location';

  @override
  String get searchGettingLocation => 'Getting your location...';

  @override
  String get origin => 'Origin';

  @override
  String get destination => 'Destination';

  @override
  String get favoritesSavedJourneys => 'Saved journeys';

  @override
  String get favoritesEmptyTitle => 'No saved journeys yet';

  @override
  String get favoritesEmptyBody =>
      'Search for a route, open its details, and tap Add to favorites.';

  @override
  String get favoritesDeleteTitle => 'Delete trip?';

  @override
  String get favoritesDeleteBody => 'Remove this journey from your favorites?';

  @override
  String get favoritesCouldNotLoad => 'Could not load saved journeys';

  @override
  String get favoritesDirect => 'Direct';

  @override
  String favoritesTransfers(int count) {
    return '$count transfers';
  }

  @override
  String get favoritesOneTransfer => '1 transfer';

  @override
  String get savedJourneyLabel => 'Saved journey';

  @override
  String get mapWalkingRoute => 'Walking route';

  @override
  String get mapRotateNorth => 'Rotate map to north';

  @override
  String get mapSearchRoutesHint => 'Search routes to see options here.';

  @override
  String get mapLoading => 'Loading…';

  @override
  String mapLoadMoreTripsWithRemaining(int count, int remaining) {
    return 'Load $count more trips ($remaining left)';
  }

  @override
  String mapLoadMoreTrips(int count, String tripWord) {
    return 'Load $count more $tripWord';
  }

  @override
  String mapLoadNextTrips(int count) {
    return 'Load next $count trips';
  }

  @override
  String get mapTripSingular => 'trip';

  @override
  String get mapTripPlural => 'trips';

  @override
  String get mapNoTransfers => 'No transfers';

  @override
  String mapTransfers(int count) {
    return '$count transfers';
  }

  @override
  String get mapOneTransfer => '1 transfer';

  @override
  String get mapAddToFavorites => 'Add to favorites';

  @override
  String get mapSteps => 'Steps';

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
  String get transitTrolleybus => 'Trolleybus';

  @override
  String get transitTram => 'Tram';

  @override
  String get transitTrain => 'Train';

  @override
  String get transitMetro => 'Metro';

  @override
  String get transitWalk => 'Walk';

  @override
  String get transitGeneric => 'Transit';
}
