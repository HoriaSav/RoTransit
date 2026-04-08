import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../auth/state/session_provider.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';

const _guestDeviceUserId = 'guest-local-user';

final savedJourneysProvider = FutureProvider<List<SavedJourneyVm>>((ref) async {
  final user = ref.watch(sessionProvider);
  final deviceUserId = user?.id ?? _guestDeviceUserId;
  final local =
      await ref.read(localSavedRoutesRepositoryProvider).getJourneys(deviceUserId);

  // When auth is bypassed, show local guest journeys.
  if (user == null) return local;

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
  return local;
});

const _placeholderCityId = '00000000-0000-0000-0000-000000000001';

Future<String> _resolveCityId(Ref ref) async {
  final currentCityId = ref.read(searchMapStateProvider).cityId;
  if (!ApiConfig.useBackend) {
    return currentCityId;
  }
  if (currentCityId.isNotEmpty && currentCityId != _placeholderCityId) {
    return currentCityId;
  }
  final cities = await ref.read(routeApiRepositoryProvider).getCities();
  if (cities.isNotEmpty) {
    final city = cities.first;
    // Persist resolved city context so all tabs can use it.
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: city.id,
          cityName: city.name,
        );
    return city.id;
  }
  return currentCityId;
}

final busesProvider = FutureProvider<List<BusLine>>((ref) async {
  final cityId = await _resolveCityId(ref);
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
