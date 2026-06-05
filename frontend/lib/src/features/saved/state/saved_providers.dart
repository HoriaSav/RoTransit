import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../auth/state/session_provider.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';

const _guestDeviceUserId = 'guest-local-user';
const _previewPlaceholderCityId = '00000000-0000-0000-0000-000000000001';

/// Bumped after a pack is saved so bus providers reload without restart.
final offlinePackRevisionProvider = StateProvider<int>((ref) => 0);

final cityOfflinePackInstalledProvider = FutureProvider<bool>((ref) async {
  if (!ApiConfig.useBackend) return true;
  ref.watch(offlinePackRevisionProvider);
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  if (cityId.isEmpty || cityId == _previewPlaceholderCityId) return false;
  final meta = await ref
      .read(offlineTransitCacheRepositoryProvider)
      .getMetaForCity(cityId);
  return meta != null;
});

final savedJourneysProvider = FutureProvider<List<SavedJourneyVm>>((ref) async {
  final user = ref.watch(sessionProvider);
  final deviceUserId = user?.id ?? _guestDeviceUserId;
  final local =
      await ref.read(localSavedRoutesRepositoryProvider).getJourneys(deviceUserId);

  // When auth is bypassed, show local guest journeys.
  if (user == null) return local;

  try {
    final remote = await ref.read(routeApiRepositoryProvider).getSavedRoutes(
          deviceUserId: deviceUserId,
        );
    final mappedRemote = remote
        .map(
          (e) => SavedJourneyVm(
            id: e.id,
            label: e.label,
            route: decodeRouteMetadata(e.routeMetadata),
            createdAt: e.createdAt,
            cityId: e.cityId,
            remoteRouteId: e.id,
            deviceUserId: deviceUserId,
          ),
        )
        .toList();
    if (mappedRemote.isNotEmpty) return mappedRemote;
  } on DioException {
    // Offline or server unreachable — use SQLite copy.
  } catch (_) {
    // Any other remote failure — still show local journeys.
  }
  return local;
});

final deleteSavedJourneyControllerProvider =
    Provider<DeleteSavedJourneyController>(
  (ref) => DeleteSavedJourneyController(ref),
);

class DeleteSavedJourneyController {
  DeleteSavedJourneyController(this._ref);
  final Ref _ref;

  Future<void> deleteJourney(SavedJourneyVm journey) async {
    final user = _ref.read(sessionProvider);
    final deviceUserId = user?.id ?? _guestDeviceUserId;
    final localPk = int.tryParse(journey.id);

    if (localPk != null) {
      await _ref
          .read(localSavedRoutesRepositoryProvider)
          .deleteByLocalId(localPk);
    }

    if (user != null && ApiConfig.useBackend) {
      final apiRouteId = journey.remoteRouteId ??
          (localPk == null ? journey.id : null);
      if (apiRouteId != null && apiRouteId.isNotEmpty) {
        try {
          await _ref.read(routeApiRepositoryProvider).deleteSavedRoute(
                routeId: apiRouteId,
                deviceUserId: deviceUserId,
              );
        } catch (_) {}
      }
    }

    _ref.invalidate(savedJourneysProvider);
  }
}

Future<String> _resolveCityId(Ref ref) async {
  final current = ref.read(searchMapStateProvider);
  final currentCityId = current.cityId;
  final currentCityName = current.cityName;
  if (!ApiConfig.useBackend) {
    return currentCityId;
  }
  try {
    final cities = await ref.read(routeApiRepositoryProvider).getCities();
    if (cities.isEmpty) {
      return currentCityId;
    }
    for (final city in cities) {
      if (city.id == currentCityId) {
        return city.id;
      }
    }
    final byName = cities.where(
      (city) =>
          city.name.trim().toLowerCase() == currentCityName.trim().toLowerCase(),
    );
    final resolved = byName.isNotEmpty ? byName.first : cities.first;
    // Keep frontend context aligned with backend IDs that may change across DB resets.
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: resolved.id,
          cityName: resolved.name,
        );
    return resolved.id;
  } on DioException {
    // Offline/unreachable backend: keep using current or fallback to last cached offline city.
    if (currentCityId.isNotEmpty) return currentCityId;
    final cachedCityId = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getLatestCachedCityId();
    if (cachedCityId != null) {
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: cachedCityId,
            cityName: currentCityName.isEmpty ? 'Offline city' : currentCityName,
          );
      return cachedCityId;
    }
    return currentCityId;
  }
}

final busesProvider = FutureProvider<List<BusLine>>((ref) async {
  ref.watch(offlinePackRevisionProvider);
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  if (ApiConfig.useBackend) {
    final meta = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getMetaForCity(cityId);
    if (meta == null) return const [];
  }
  return ref.read(routeApiRepositoryProvider).listBuses(cityId: cityId);
});

final routeStopsProvider = FutureProvider.family<List<RouteStop>,
    ({String routeId, String? directionId})>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  return ref.read(routeApiRepositoryProvider).getRouteStops(
        cityId: cityId,
        routeId: args.routeId,
        directionId: args.directionId,
      );
});

final routeTimetableProvider = FutureProvider.family<StopTimetable,
    ({String routeId, String stopId, DateTime serviceDate, String? directionId})>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  return ref.read(routeApiRepositoryProvider).getTimetable(
        cityId: cityId,
        routeId: args.routeId,
        stopId: args.stopId,
        serviceDate: args.serviceDate,
        directionId: args.directionId,
      );
});
