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

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navBus.
  ///
  /// In en, this message translates to:
  /// **'Timetable'**
  String get navBus;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

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

  /// No description provided for @settingsDataAsOf.
  ///
  /// In en, this message translates to:
  /// **'Brașov data as of'**
  String get settingsDataAsOf;

  /// No description provided for @settingsFaresTitle.
  ///
  /// In en, this message translates to:
  /// **'Fares & tickets'**
  String get settingsFaresTitle;

  /// No description provided for @settingsFaresSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Urban vs metropolitan · where to buy'**
  String get settingsFaresSubtitle;

  /// No description provided for @faresSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'RATBV fares (static guide)'**
  String get faresSheetTitle;

  /// No description provided for @faresSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Urban (inside Brașov): about 5 RON per ride on the standard ticket (confirm on ratbv.ro — prices change).\n\nMetropolitan / zone tickets: higher fares for trips into nearby communes (roughly 7–12 RON depending on zone in the GTFS fare table).\n\nBuy tickets: 24pay app, RATBV ticket machines/kiosks, and other channels listed on the operator site. This app does not sell tickets.'**
  String get faresSheetBody;

  /// No description provided for @busTabTimetablesNotDownloadedTitle.
  ///
  /// In en, this message translates to:
  /// **'Timetables not available'**
  String get busTabTimetablesNotDownloadedTitle;

  /// No description provided for @busTabTimetablesNotDownloadedBody.
  ///
  /// In en, this message translates to:
  /// **'Timetables are available only for Brașov for now. Choose Brașov in Settings.'**
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

  /// No description provided for @favoriteLineAdd.
  ///
  /// In en, this message translates to:
  /// **'Favorite line'**
  String get favoriteLineAdd;

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

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get openSettings;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link'**
  String get linkOpenFailed;

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

  /// No description provided for @errorUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnexpectedError;

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

  /// No description provided for @searchSelectStop.
  ///
  /// In en, this message translates to:
  /// **'Select stop'**
  String get searchSelectStop;

  /// No description provided for @favoritesCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load favorites'**
  String get favoritesCouldNotLoad;

  /// No description provided for @favoritesCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save favorite'**
  String get favoritesCouldNotSave;

  /// No description provided for @favoritesStopsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stops'**
  String get favoritesStopsTitle;

  /// No description provided for @favoritesStopsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorite stops yet. Open a stop on the map and tap the star.'**
  String get favoritesStopsEmpty;

  /// No description provided for @favoritesLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get favoritesLinesTitle;

  /// No description provided for @favoritesLinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorite lines yet. In Timetable, tap the star next to a line.'**
  String get favoritesLinesEmpty;

  /// No description provided for @favoriteStopAdd.
  ///
  /// In en, this message translates to:
  /// **'Favorite stop'**
  String get favoriteStopAdd;

  /// No description provided for @favoriteRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite'**
  String get favoriteRemove;

  /// No description provided for @mapRotateNorth.
  ///
  /// In en, this message translates to:
  /// **'Rotate map to north'**
  String get mapRotateNorth;

  /// No description provided for @mapSearchStationsHint.
  ///
  /// In en, this message translates to:
  /// **'Search Brașov stations'**
  String get mapSearchStationsHint;

  /// No description provided for @mapScheduleNotLive.
  ///
  /// In en, this message translates to:
  /// **'Schedule times · not live GPS'**
  String get mapScheduleNotLive;

  /// No description provided for @stopBoardWindow.
  ///
  /// In en, this message translates to:
  /// **'Next {minutes} min'**
  String stopBoardWindow(int minutes);

  /// No description provided for @stopBoardCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load schedule'**
  String get stopBoardCouldNotLoad;

  /// No description provided for @stopBoardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No departures in the next {minutes} minutes'**
  String stopBoardEmpty(int minutes);

  /// No description provided for @stopBoardShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show next {minutes} minutes'**
  String stopBoardShowMore(int minutes);

  /// No description provided for @stopBoardUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String stopBoardUntil(String time);

  /// No description provided for @stopBoardEmptyUntil.
  ///
  /// In en, this message translates to:
  /// **'No departures until {time}'**
  String stopBoardEmptyUntil(String time);

  /// No description provided for @stopBoardFeedEnded.
  ///
  /// In en, this message translates to:
  /// **'Timetable data ended on {date}. Update the app to see departures.'**
  String stopBoardFeedEnded(String date);

  /// No description provided for @stopOpenInGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get stopOpenInGoogleMaps;

  /// No description provided for @busSearchLineHint.
  ///
  /// In en, this message translates to:
  /// **'Search line number or name'**
  String get busSearchLineHint;
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
