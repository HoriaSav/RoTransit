import 'package:rotransit_frontend/l10n/app_localizations.dart';

import 'app_user_message.dart';

extension AppUserMessageLocalization on AppLocalizations {
  String localizeUserMessage(AppUserMessageId id) {
    return switch (id) {
      AppUserMessageId.completeSearchFields => errorCompleteSearchFields,
      AppUserMessageId.selectStationsFromPicker => errorSelectStationsFromPicker,
      AppUserMessageId.cityContextUnavailable => errorCityContextUnavailable,
      AppUserMessageId.searchRequiresInternet => errorSearchRequiresInternet,
      AppUserMessageId.noRoutesFound => errorNoRoutesFound,
      AppUserMessageId.serverUnreachable => errorServerUnreachable,
      AppUserMessageId.serverTimeout => errorServerTimeout,
      AppUserMessageId.routingUnavailable => errorRoutingUnavailable,
      AppUserMessageId.invalidSearchParams => errorInvalidSearchParams,
      AppUserMessageId.cityNotFound => errorCityNotFound,
      AppUserMessageId.unexpectedError => errorUnexpectedError,
      AppUserMessageId.routeShapeSimplified => errorRouteShapeSimplified,
      AppUserMessageId.loadMoreRoutesFailed => errorLoadMoreRoutesFailed,
      AppUserMessageId.addedToFavorites => successAddedToFavorites,
      AppUserMessageId.mapPickHint => '',
    };
  }

  String transitModeLabel(String mode) {
    final normalized = mode.trim().toUpperCase();
    return switch (normalized) {
      'BUS' => transitBus,
      'TROLLEYBUS' => transitTrolleybus,
      'TRAM' => transitTram,
      'RAIL' => transitTrain,
      'SUBWAY' => transitMetro,
      'WALK' => transitWalk,
      _ => normalized.isEmpty ? transitGeneric : mode.trim(),
    };
  }

  String favoritesTransferLabel(int transfers) {
    if (transfers == 0) return favoritesDirect;
    if (transfers == 1) return favoritesOneTransfer;
    return favoritesTransfers(transfers);
  }

  String mapTransferLabel(int transfers) {
    if (transfers == 0) return mapNoTransfers;
    if (transfers == 1) return mapOneTransfer;
    return mapTransfers(transfers);
  }
}
