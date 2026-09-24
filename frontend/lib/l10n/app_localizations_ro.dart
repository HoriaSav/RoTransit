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
  String get offlineTimetables => 'Orare offline';

  @override
  String get offlinePackWhatItCovers =>
      'Păstrează liniile și orarele pe telefon. Căutarea unei rute de la A la B tot are nevoie de internet.';

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
  String get offlinePackChooseCityFirst => 'Alege mai întâi un oraș';

  @override
  String get offlinePackNoneYet => 'Nedescărcat';

  @override
  String get offlinePackAvailableOnDevice => 'Disponibil pe dispozitiv';

  @override
  String offlinePackDownloaded(String date) {
    return 'Descărcat $date';
  }

  @override
  String offlinePackDownloadedWithWeek(String date, String week) {
    return 'Descărcat $date · săpt. $week';
  }

  @override
  String get offlineMetaEndpointMissing =>
      'Indisponibil — implementează GET /api/buses/offline-pack-meta pe server';

  @override
  String get timetableDownloadSourceBus => 'Orare autobuz';

  @override
  String get timetableDownloadConfirmTitle => 'Descarci orarele?';

  @override
  String timetableDownloadConfirmMessage(String cityName) {
    return 'Descarci liniile și orarele de autobuz pentru $cityName pe telefon? Căutarea unei rute de la A la B tot are nevoie de internet. Poate consuma date mobile.';
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
  String get timetableDownloadAlreadyUpToDate =>
      'Orarele sunt deja descărcate și actualizate';

  @override
  String get busTabTimetablesNotDownloadedTitle => 'Orare nedescărcate';

  @override
  String get busTabTimetablesNotDownloadedBody =>
      'Descarcă orarele de autobuz pentru acest oraș din Setări ca să poți vedea liniile și programul.';

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
  String busFrom(String destination) {
    return 'De la: $destination';
  }

  @override
  String busLineTitle(String short, String long) {
    return 'Autobuz $short · $long';
  }

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

  @override
  String get commonCancel => 'Anulează';

  @override
  String get commonDelete => 'Șterge';

  @override
  String get commonBack => 'Înapoi';

  @override
  String get openSettings => 'Setări';

  @override
  String get errorCompleteSearchFields =>
      'Completează Plecare, Destinație, data și ora.';

  @override
  String get errorSelectStationsFromPicker =>
      'Selectează ambele stații din listă sau de pe hartă.';

  @override
  String get errorCityContextUnavailable =>
      'Nu s-a putut încărca orașul. Încearcă din nou.';

  @override
  String get errorSearchRequiresInternet =>
      'Căutarea rutelor necesită conexiune la internet.';

  @override
  String get errorNoRoutesFound =>
      'Nu s-au găsit rute pentru această călătorie.';

  @override
  String get errorServerUnreachable =>
      'Serverul nu poate fi contactat. Verifică conexiunea și încearcă din nou.';

  @override
  String get errorServerTimeout =>
      'Serverul a răspuns prea greu. Încearcă din nou.';

  @override
  String get errorRoutingUnavailable =>
      'Planificarea călătoriei este temporar indisponibilă.';

  @override
  String get errorInvalidSearchParams => 'Verifică stațiile, data și ora.';

  @override
  String get errorCityNotFound => 'Acest oraș nu este disponibil încă.';

  @override
  String get errorUnexpectedError => 'Ceva nu a funcționat. Încearcă din nou.';

  @override
  String get errorRouteShapeSimplified =>
      'Nu s-au putut încărca detaliile complete. Se afișează o variantă simplificată.';

  @override
  String get errorLoadMoreRoutesFailed =>
      'Nu s-au putut încărca mai multe rute. Încearcă din nou.';

  @override
  String get successAddedToFavorites => 'Adăugat la favorite';

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
  String get searchFrom => 'De la';

  @override
  String get searchTo => 'Spre';

  @override
  String get searchDate => 'Data';

  @override
  String get searchTime => 'Ora';

  @override
  String get searchButton => 'Caută';

  @override
  String get searchRecent => 'Recente';

  @override
  String get searchNoRecent => 'Nicio căutare recentă.';

  @override
  String get searchCouldNotLoadRecent =>
      'Nu s-au putut încărca căutările recente.';

  @override
  String get searchSelectDate => 'Selectează data';

  @override
  String get searchSelectTime => 'Selectează ora';

  @override
  String get searchSwapTooltip => 'Schimbă Plecare cu Destinația';

  @override
  String get searchDeparture => 'Plecare';

  @override
  String get searchDestination => 'Destinație';

  @override
  String get searchSelectStop => 'Selectează stația';

  @override
  String get searchStationHint => 'Caută stație';

  @override
  String get searchCurrentLocation => 'Locația curentă';

  @override
  String get searchSelectOnMap => 'Selectează pe hartă';

  @override
  String get searchNoNearbyStops =>
      'Nicio stație în apropiere. Caută mai sus sau folosește Selectează pe hartă.';

  @override
  String get searchNoMatches =>
      'Niciun rezultat. Încearcă alt termen sau Selectează pe hartă.';

  @override
  String get searchEnableLocationForDistance =>
      'Activează locația pentru distanță';

  @override
  String get searchWaitingForGps => 'Se așteaptă GPS...';

  @override
  String get searchUsingGps => 'Se folosește poziția GPS';

  @override
  String get searchTapToRetryLocation =>
      'Apasă pentru a reîncerca — activează locația precisă';

  @override
  String get searchGettingLocation => 'Se obține locația...';

  @override
  String get origin => 'Origine';

  @override
  String get destination => 'Destinație';

  @override
  String get favoritesSavedJourneys => 'Călătorii salvate';

  @override
  String get favoritesEmptyTitle => 'Nicio călătorie salvată';

  @override
  String get favoritesEmptyBody =>
      'Caută o rută, deschide detaliile și apasă Adaugă la favorite.';

  @override
  String get favoritesDeleteTitle => 'Ștergi călătoria?';

  @override
  String get favoritesDeleteBody => 'Elimini această călătorie din favorite?';

  @override
  String get favoritesCouldNotLoad =>
      'Nu s-au putut încărca călătoriile salvate';

  @override
  String get favoritesDirect => 'Direct';

  @override
  String favoritesTransfers(int count) {
    return '$count transferuri';
  }

  @override
  String get favoritesOneTransfer => '1 transfer';

  @override
  String get savedJourneyLabel => 'Călătorie salvată';

  @override
  String get mapWalkingRoute => 'Rută pietonală';

  @override
  String get mapRotateNorth => 'Orientează harta spre nord';

  @override
  String get mapSearchRoutesHint => 'Caută rute pentru a vedea opțiunile aici.';

  @override
  String get mapLoading => 'Se încarcă…';

  @override
  String mapLoadMoreTripsWithRemaining(int count, int remaining) {
    return 'Încarcă încă $count curse ($remaining rămase)';
  }

  @override
  String mapLoadMoreTrips(int count, String tripWord) {
    return 'Încarcă încă $count $tripWord';
  }

  @override
  String mapLoadNextTrips(int count) {
    return 'Încarcă următoarele $count curse';
  }

  @override
  String get mapTripSingular => 'cursă';

  @override
  String get mapTripPlural => 'curse';

  @override
  String get mapNoTransfers => 'Fără transferuri';

  @override
  String mapTransfers(int count) {
    return '$count transferuri';
  }

  @override
  String get mapOneTransfer => '1 transfer';

  @override
  String get mapAddToFavorites => 'Adaugă la favorite';

  @override
  String get mapSteps => 'Pași';

  @override
  String mapPriceLei(int price) {
    return '$price lei';
  }

  @override
  String mapTransfersAndPrice(String transfers, String price) {
    return '$transfers • $price';
  }

  @override
  String get transitBus => 'Autobuz';

  @override
  String get transitTrolleybus => 'Troleibuz';

  @override
  String get transitTram => 'Tramvai';

  @override
  String get transitTrain => 'Tren';

  @override
  String get transitMetro => 'Metrou';

  @override
  String get transitWalk => 'Mers pe jos';

  @override
  String get transitGeneric => 'Transport';
}
