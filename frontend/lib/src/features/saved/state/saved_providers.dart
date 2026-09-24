import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../map/data/companion_catalog.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';

/// Bumped after a pack is saved so bus providers reload without restart.
final offlinePackRevisionProvider = StateProvider<int>((ref) => 0);

final cityOfflinePackInstalledProvider = FutureProvider<bool>((ref) async {
  ref.watch(offlinePackRevisionProvider);
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  if (cityId.isEmpty) return false;
  try {
    final meta = await CompanionCatalog.instance.meta();
    if (cityId == meta.cityId ||
        isCityAvailable(cityId: cityId, cityName: kBrasovCityName)) {
      // Bundled companion pack is always on-device for Brașov.
      return true;
    }
  } catch (_) {}
  final meta = await ref
      .read(offlineTransitCacheRepositoryProvider)
      .getMetaForCity(cityId);
  return meta != null;
});

final savedJourneysProvider = FutureProvider<List<SavedJourneyVm>>((ref) async {
  return ref
      .read(localSavedRoutesRepositoryProvider)
      .getJourneys(kLocalDeviceUserId);
});

final deleteSavedJourneyControllerProvider =
    Provider<DeleteSavedJourneyController>(
  (ref) => DeleteSavedJourneyController(ref),
);

class DeleteSavedJourneyController {
  DeleteSavedJourneyController(this._ref);
  final Ref _ref;

  Future<void> deleteJourney(SavedJourneyVm journey) async {
    final localPk = int.tryParse(journey.id);

    if (localPk != null) {
      await _ref
          .read(localSavedRoutesRepositoryProvider)
          .deleteByLocalId(localPk);
    }

    _ref.invalidate(savedJourneysProvider);
  }
}

Future<String> _resolveCityId(Ref ref) async {
  final current = ref.read(searchMapStateProvider);
  final currentCityId = resolvedCityId(current.cityId);
  final currentCityName = current.cityName.trim().isEmpty
      ? kBrasovCityName
      : current.cityName;

  // Companion path: prefer local Brașov id — do not block Timetable on API.
  if (isCityAvailable(cityId: currentCityId, cityName: currentCityName) ||
      isUnresolvedCityId(current.cityId)) {
    if (current.cityId != kBrasovCityId ||
        current.cityName.trim().isEmpty) {
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: kBrasovCityId,
            cityName: kBrasovCityName,
          );
    }
    return kBrasovCityId;
  }

  try {
    final cities = await ref.read(routeApiRepositoryProvider).getCities();
    final resolved = resolveCatalogCity(
      cities,
      preferredId: currentCityId,
      preferredName: currentCityName,
    );
    if (resolved.id != current.cityId || resolved.name != current.cityName) {
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: resolved.id,
            cityName: resolved.name,
          );
    }
    return resolved.id;
  } on DioException {
    if (!isUnresolvedCityId(current.cityId)) return currentCityId;
    final cachedCityId = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getLatestCachedCityId();
    if (cachedCityId != null && !isUnresolvedCityId(cachedCityId)) {
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: cachedCityId,
            cityName: currentCityName,
          );
      return cachedCityId;
    }
    return kBrasovCityId;
  }
}

bool _useCompanion(String cityId) {
  return cityId == kBrasovCityId ||
      isCityAvailable(cityId: cityId, cityName: kBrasovCityName);
}

final busesProvider = FutureProvider<List<BusLine>>((ref) async {
  ref.watch(offlinePackRevisionProvider);
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  if (_useCompanion(cityId)) {
    try {
      return await CompanionCatalog.instance.listBuses();
    } catch (_) {
      // Fall through to LocalDb / API path.
    }
  }
  final meta = await ref
      .read(offlineTransitCacheRepositoryProvider)
      .getMetaForCity(cityId);
  if (meta == null && !_useCompanion(cityId)) return const [];
  return ref.read(routeApiRepositoryProvider).listBuses(cityId: cityId);
});

final routeStopsProvider = FutureProvider.family<List<RouteStop>,
    ({String routeId, String? directionId})>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  if (_useCompanion(cityId)) {
    try {
      final stops = await CompanionCatalog.instance.routeStops(
        routeId: args.routeId,
        directionId: args.directionId ?? '0',
      );
      if (stops.isNotEmpty) return stops;
    } catch (_) {}
  }
  return ref.read(routeApiRepositoryProvider).getRouteStops(
        cityId: cityId,
        routeId: args.routeId,
        directionId: args.directionId,
      );
});

final routeTimetableProvider = FutureProvider.family<StopTimetable,
    ({
      String routeId,
      String stopId,
      DateTime serviceDate,
      String? directionId
    })>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  if (_useCompanion(cityId)) {
    try {
      return await CompanionCatalog.instance.timetable(
        routeId: args.routeId,
        stopId: args.stopId,
        serviceDate: args.serviceDate,
        directionId: args.directionId ?? '0',
      );
    } catch (_) {}
  }
  return ref.read(routeApiRepositoryProvider).getTimetable(
        cityId: cityId,
        routeId: args.routeId,
        stopId: args.stopId,
        serviceDate: args.serviceDate,
        directionId: args.directionId,
      );
});
