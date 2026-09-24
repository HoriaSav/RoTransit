import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ro.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('de'),
    Locale('en'),
    Locale('ro')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RoTransit'**
  String get appTitle;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get navBus;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @teTransport.
  ///
  /// In en, this message translates to:
  /// **'TE transport'**
  String get teTransport;

  /// No description provided for @teTransportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Student transport'**
  String get teTransportSubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRomanian.
  ///
  /// In en, this message translates to:
  /// **'Romanian'**
  String get languageRomanian;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @offlineTimetables.
  ///
  /// In en, this message translates to:
  /// **'Offline timetables'**
  String get offlineTimetables;

  /// No description provided for @offlinePackWhatItCovers.
  ///
  /// In en, this message translates to:
  /// **'Stores bus lines and stop timetables on the phone. Searching a trip from A to B still needs internet.'**
  String get offlinePackWhatItCovers;

  /// No description provided for @offlineOnDevicePack.
  ///
  /// In en, this message translates to:
  /// **'On-device pack: {version}'**
  String offlineOnDevicePack(String version);

  /// No description provided for @offlineServerMeta.
  ///
  /// In en, this message translates to:
  /// **'Server meta (for updates): {meta}'**
  String offlineServerMeta(String meta);

  /// No description provided for @offlineUpdatingBackground.
  ///
  /// In en, this message translates to:
  /// **'Downloading timetables…'**
  String get offlineUpdatingBackground;

  /// No description provided for @offlineDownloadProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String offlineDownloadProgressPercent(int percent);

  /// No description provided for @offlineDownloadEtaMinutes.
  ///
  /// In en, this message translates to:
  /// **'~{count} min left'**
  String offlineDownloadEtaMinutes(int count);

  /// No description provided for @offlineDownloadEtaSeconds.
  ///
  /// In en, this message translates to:
  /// **'~{count} sec left'**
  String offlineDownloadEtaSeconds(int count);

  /// No description provided for @offlineDownloadReceived.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {size}…'**
  String offlineDownloadReceived(String size);

  /// No description provided for @offlineDownloadSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving timetables on device…'**
  String get offlineDownloadSaving;

  /// No description provided for @offlineDownloadReceivedWithElapsed.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {size} · {seconds} sec'**
  String offlineDownloadReceivedWithElapsed(String size, int seconds);

  /// No description provided for @offlinePackChooseCityFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a city first'**
  String get offlinePackChooseCityFirst;

  /// No description provided for @offlinePackNoneYet.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get offlinePackNoneYet;

  /// No description provided for @offlinePackAvailableOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Available on device'**
  String get offlinePackAvailableOnDevice;

  /// No description provided for @offlinePackDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {date}'**
  String offlinePackDownloaded(String date);

  /// No description provided for @offlinePackDownloadedWithWeek.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {date} · week {week}'**
  String offlinePackDownloadedWithWeek(String date, String week);

  /// No description provided for @offlineMetaEndpointMissing.
  ///
  /// In en, this message translates to:
  /// **'Not available — deploy GET /api/buses/offline-pack-meta on the server'**
  String get offlineMetaEndpointMissing;

  /// No description provided for @timetableDownloadSourceBus.
  ///
  /// In en, this message translates to:
  /// **'Bus timetables'**
  String get timetableDownloadSourceBus;

  /// No description provided for @timetableDownloadConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Download timetables?'**
  String get timetableDownloadConfirmTitle;

  /// No description provided for @timetableDownloadConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Download bus lines and stop timetables for {cityName} onto this phone? Searching a trip from A to B still needs internet. This may use mobile data.'**
  String timetableDownloadConfirmMessage(String cityName);

  /// No description provided for @timetableDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get timetableDownloadAction;

  /// No description provided for @timetableDownloadSuccess.
  ///
  /// In en, this message translates to:
  /// **'Timetables downloaded for {cityName}'**
  String timetableDownloadSuccess(String cityName);

  /// No description provided for @timetableDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download timetables'**
  String get timetableDownloadFailed;

  /// No description provided for @timetableDownloadOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to download timetables'**
  String get timetableDownloadOffline;

  /// No description provided for @timetableDownloadAlreadyUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Timetables are already downloaded and up to date'**
  String get timetableDownloadAlreadyUpToDate;

  /// No description provided for @busTabTimetablesNotDownloadedTitle.
  ///
  /// In en, this message translates to:
  /// **'Timetables not downloaded'**
  String get busTabTimetablesNotDownloadedTitle;

  /// No description provided for @busTabTimetablesNotDownloadedBody.
  ///
  /// In en, this message translates to:
  /// **'Download bus timetables for this city in Settings to browse lines and schedules.'**
  String get busTabTimetablesNotDownloadedBody;

  /// No description provided for @busTabOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get busTabOpenSettings;

  /// No description provided for @busTabUrban.
  ///
  /// In en, this message translates to:
  /// **'Urban'**
  String get busTabUrban;

  /// No description provided for @busTabRural.
  ///
  /// In en, this message translates to:
  /// **'Rural'**
  String get busTabRural;

  /// No description provided for @busTabTe.
  ///
  /// In en, this message translates to:
  /// **'TE'**
  String get busTabTe;

  /// No description provided for @busNoLinesFound.
  ///
  /// In en, this message translates to:
  /// **'No bus lines found.'**
  String get busNoLinesFound;

  /// No description provided for @busCouldNotLoadLines.
  ///
  /// In en, this message translates to:
  /// **'Could not load bus lines'**
  String get busCouldNotLoadLines;

  /// No description provided for @busNoLinesInGroup.
  ///
  /// In en, this message translates to:
  /// **'No lines in this group.'**
  String get busNoLinesInGroup;

  /// No description provided for @busRouteFallback.
  ///
  /// In en, this message translates to:
  /// **'Bus route'**
  String get busRouteFallback;

  /// No description provided for @busLineFallback.
  ///
  /// In en, this message translates to:
  /// **'Bus {number}'**
  String busLineFallback(String number);

  /// No description provided for @busBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get busBack;

  /// No description provided for @busReverseDirection.
  ///
  /// In en, this message translates to:
  /// **'Reverse direction'**
  String get busReverseDirection;

  /// No description provided for @busNoStopsFound.
  ///
  /// In en, this message translates to:
  /// **'No stops found.'**
  String get busNoStopsFound;

  /// No description provided for @busCouldNotLoadStops.
  ///
  /// In en, this message translates to:
  /// **'Could not load route stops'**
  String get busCouldNotLoadStops;

  /// No description provided for @busCouldNotLoadTimetable.
  ///
  /// In en, this message translates to:
  /// **'Could not load timetable'**
  String get busCouldNotLoadTimetable;

  /// No description provided for @busNoDepartures.
  ///
  /// In en, this message translates to:
  /// **'No departures for this stop.'**
  String get busNoDepartures;

  /// No description provided for @busTowards.
  ///
  /// In en, this message translates to:
  /// **'Towards: {destination}'**
  String busTowards(String destination);

  /// No description provided for @busFrom.
  ///
  /// In en, this message translates to:
  /// **'From: {destination}'**
  String busFrom(String destination);

  /// No description provided for @busLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Bus {short} · {long}'**
  String busLineTitle(String short, String long);

  /// No description provided for @timetableHour.
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get timetableHour;

  /// No description provided for @timetableWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Mon-Fri'**
  String get timetableWeekdays;

  /// No description provided for @timetableSaturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get timetableSaturday;

  /// No description provided for @timetableSunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get timetableSunday;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get termsOfUse;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get contactUs;

  /// No description provided for @countryLabel.
  ///
  /// In en, this message translates to:
  /// **'Country: {country}'**
  String countryLabel(String country);

  /// No description provided for @cityChangedTo.
  ///
  /// In en, this message translates to:
  /// **'City changed to {name}'**
  String cityChangedTo(String name);

  /// No description provided for @cityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get cityUnavailable;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again quickly to exit the app'**
  String get pressBackAgainToExit;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get openSettings;

  /// No description provided for @errorCompleteSearchFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in From, To, date, and time.'**
  String get errorCompleteSearchFields;

  /// No description provided for @errorSelectStationsFromPicker.
  ///
  /// In en, this message translates to:
  /// **'Select both stations from the list or map.'**
  String get errorSelectStationsFromPicker;

  /// No description provided for @errorCityContextUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not load your city. Try again later.'**
  String get errorCityContextUnavailable;

  /// No description provided for @errorSearchRequiresInternet.
  ///
  /// In en, this message translates to:
  /// **'Route search needs an internet connection.'**
  String get errorSearchRequiresInternet;

  /// No description provided for @errorNoRoutesFound.
  ///
  /// In en, this message translates to:
  /// **'No routes found for this trip.'**
  String get errorNoRoutesFound;

  /// No description provided for @errorServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection and try again.'**
  String get errorServerUnreachable;

  /// No description provided for @errorServerTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. Try again.'**
  String get errorServerTimeout;

  /// No description provided for @errorRoutingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Trip planning is temporarily unavailable.'**
  String get errorRoutingUnavailable;

  /// No description provided for @errorInvalidSearchParams.
  ///
  /// In en, this message translates to:
  /// **'Check your stations, date, and time.'**
  String get errorInvalidSearchParams;

  /// No description provided for @errorCityNotFound.
  ///
  /// In en, this message translates to:
  /// **'This city is not available yet.'**
  String get errorCityNotFound;

  /// No description provided for @errorUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnexpectedError;

  /// No description provided for @errorRouteShapeSimplified.
  ///
  /// In en, this message translates to:
  /// **'Could not load full route details. Showing a simplified view.'**
  String get errorRouteShapeSimplified;

  /// No description provided for @errorLoadMoreRoutesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load more routes. Try again.'**
  String get errorLoadMoreRoutesFailed;

  /// No description provided for @successAddedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get successAddedToFavorites;

  /// No description provided for @locationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Location services are turned off on this device.'**
  String get locationServicesOff;

  /// No description provided for @locationPermissionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Location permission is blocked. Open Settings to allow precise location.'**
  String get locationPermissionBlocked;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission was denied.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPreciseRequired.
  ///
  /// In en, this message translates to:
  /// **'Enable Precise Location in Settings for accurate stop distances.'**
  String get locationPreciseRequired;

  /// No description provided for @locationGpsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not get a reliable GPS fix. Try outdoors, enable precise location, or use Select on map.'**
  String get locationGpsFailed;

  /// No description provided for @searchFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get searchFrom;

  /// No description provided for @searchTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get searchTo;

  /// No description provided for @searchDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get searchDate;

  /// No description provided for @searchTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get searchTime;

  /// No description provided for @searchButton.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchButton;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get searchRecent;

  /// No description provided for @searchNoRecent.
  ///
  /// In en, this message translates to:
  /// **'No recent searches yet.'**
  String get searchNoRecent;

  /// No description provided for @searchCouldNotLoadRecent.
  ///
  /// In en, this message translates to:
  /// **'Could not load recent searches.'**
  String get searchCouldNotLoadRecent;

  /// No description provided for @searchSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get searchSelectDate;

  /// No description provided for @searchSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get searchSelectTime;

  /// No description provided for @searchSwapTooltip.
  ///
  /// In en, this message translates to:
  /// **'Swap From and To'**
  String get searchSwapTooltip;

  /// No description provided for @searchDeparture.
  ///
  /// In en, this message translates to:
  /// **'Departure'**
  String get searchDeparture;

  /// No description provided for @searchDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get searchDestination;

  /// No description provided for @searchSelectStop.
  ///
  /// In en, this message translates to:
  /// **'Select stop'**
  String get searchSelectStop;

  /// No description provided for @searchStationHint.
  ///
  /// In en, this message translates to:
  /// **'Search station'**
  String get searchStationHint;

  /// No description provided for @searchCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get searchCurrentLocation;

  /// No description provided for @searchSelectOnMap.
  ///
  /// In en, this message translates to:
  /// **'Select on map'**
  String get searchSelectOnMap;

  /// No description provided for @searchNoNearbyStops.
  ///
  /// In en, this message translates to:
  /// **'No nearby stops. Search above or use Select on map.'**
  String get searchNoNearbyStops;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches for your search. Try another query or Select on map.'**
  String get searchNoMatches;

  /// No description provided for @searchEnableLocationForDistance.
  ///
  /// In en, this message translates to:
  /// **'Enable location for distance'**
  String get searchEnableLocationForDistance;

  /// No description provided for @searchWaitingForGps.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS...'**
  String get searchWaitingForGps;

  /// No description provided for @searchUsingGps.
  ///
  /// In en, this message translates to:
  /// **'Using your GPS position'**
  String get searchUsingGps;

  /// No description provided for @searchTapToRetryLocation.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry — enable precise location'**
  String get searchTapToRetryLocation;

  /// No description provided for @searchGettingLocation.
  ///
  /// In en, this message translates to:
  /// **'Getting your location...'**
  String get searchGettingLocation;

  /// No description provided for @origin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get origin;

  /// No description provided for @destination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destination;

  /// No description provided for @favoritesSavedJourneys.
  ///
  /// In en, this message translates to:
  /// **'Saved journeys'**
  String get favoritesSavedJourneys;

  /// No description provided for @favoritesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved journeys yet'**
  String get favoritesEmptyTitle;

  /// No description provided for @favoritesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Search for a route, open its details, and tap Add to favorites.'**
  String get favoritesEmptyBody;

  /// No description provided for @favoritesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete trip?'**
  String get favoritesDeleteTitle;

  /// No description provided for @favoritesDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this journey from your favorites?'**
  String get favoritesDeleteBody;

  /// No description provided for @favoritesCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load saved journeys'**
  String get favoritesCouldNotLoad;

  /// No description provided for @favoritesDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get favoritesDirect;

  /// No description provided for @favoritesTransfers.
  ///
  /// In en, this message translates to:
  /// **'{count} transfers'**
  String favoritesTransfers(int count);

  /// No description provided for @favoritesOneTransfer.
  ///
  /// In en, this message translates to:
  /// **'1 transfer'**
  String get favoritesOneTransfer;

  /// No description provided for @savedJourneyLabel.
  ///
  /// In en, this message translates to:
  /// **'Saved journey'**
  String get savedJourneyLabel;

  /// No description provided for @mapWalkingRoute.
  ///
  /// In en, this message translates to:
  /// **'Walking route'**
  String get mapWalkingRoute;

  /// No description provided for @mapRotateNorth.
  ///
  /// In en, this message translates to:
  /// **'Rotate map to north'**
  String get mapRotateNorth;

  /// No description provided for @mapSearchRoutesHint.
  ///
  /// In en, this message translates to:
  /// **'Search routes to see options here.'**
  String get mapSearchRoutesHint;

  /// No description provided for @mapLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get mapLoading;

  /// No description provided for @mapLoadMoreTripsWithRemaining.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more trips ({remaining} left)'**
  String mapLoadMoreTripsWithRemaining(int count, int remaining);

  /// No description provided for @mapLoadMoreTrips.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more {tripWord}'**
  String mapLoadMoreTrips(int count, String tripWord);

  /// No description provided for @mapLoadNextTrips.
  ///
  /// In en, this message translates to:
  /// **'Load next {count} trips'**
  String mapLoadNextTrips(int count);

  /// No description provided for @mapTripSingular.
  ///
  /// In en, this message translates to:
  /// **'trip'**
  String get mapTripSingular;

  /// No description provided for @mapTripPlural.
  ///
  /// In en, this message translates to:
  /// **'trips'**
  String get mapTripPlural;

  /// No description provided for @mapNoTransfers.
  ///
  /// In en, this message translates to:
  /// **'No transfers'**
  String get mapNoTransfers;

  /// No description provided for @mapTransfers.
  ///
  /// In en, this message translates to:
  /// **'{count} transfers'**
  String mapTransfers(int count);

  /// No description provided for @mapOneTransfer.
  ///
  /// In en, this message translates to:
  /// **'1 transfer'**
  String get mapOneTransfer;

  /// No description provided for @mapAddToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get mapAddToFavorites;

  /// No description provided for @mapSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get mapSteps;

  /// No description provided for @mapPriceLei.
  ///
  /// In en, this message translates to:
  /// **'{price} lei'**
  String mapPriceLei(int price);

  /// No description provided for @mapTransfersAndPrice.
  ///
  /// In en, this message translates to:
  /// **'{transfers} • {price}'**
  String mapTransfersAndPrice(String transfers, String price);

  /// No description provided for @transitBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get transitBus;

  /// No description provided for @transitTrolleybus.
  ///
  /// In en, this message translates to:
  /// **'Trolleybus'**
  String get transitTrolleybus;

  /// No description provided for @transitTram.
  ///
  /// In en, this message translates to:
  /// **'Tram'**
  String get transitTram;

  /// No description provided for @transitTrain.
  ///
  /// In en, this message translates to:
  /// **'Train'**
  String get transitTrain;

  /// No description provided for @transitMetro.
  ///
  /// In en, this message translates to:
  /// **'Metro'**
  String get transitMetro;

  /// No description provided for @transitWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get transitWalk;

  /// No description provided for @transitGeneric.
  ///
  /// In en, this message translates to:
  /// **'Transit'**
  String get transitGeneric;
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
      <String>['de', 'en', 'ro'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'ro':
      return AppLocalizationsRo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
