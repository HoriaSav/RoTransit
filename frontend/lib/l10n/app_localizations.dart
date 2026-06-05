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

  /// No description provided for @offlinePackNotAvailablePreview.
  ///
  /// In en, this message translates to:
  /// **'Not available in preview mode'**
  String get offlinePackNotAvailablePreview;

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
  /// **'Download offline bus timetables for {cityName}? This may use mobile data.'**
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
