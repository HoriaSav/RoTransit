import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../map/data/companion_catalog.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';

final cityOfflinePackInstalledProvider = FutureProvider<bool>((ref) async {
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  // Only Brașov has timetables: the pack is bundled, installed once it opens.
  if (!_useCompanion(cityId)) return false;
  await CompanionCatalog.instance.meta();
  return true;
});

/// Pure city id for providers. Never call [SearchMapController.setCityContext]
/// here — Riverpod forbids modifying providers during FutureProvider build,
/// and doing so can leave Timetable providers in a permanent error/empty state.
Future<String> _resolveCityId(Ref ref) async {
  final current = ref.read(searchMapStateProvider);
  final currentCityId = resolvedCityId(current.cityId);
  final currentCityName =
      current.cityName.trim().isEmpty ? kBrasovCityName : current.cityName;

  // Companion / unresolved → Brașov local id (no mutation during build).
  if (isCityAvailable(cityId: currentCityId, cityName: currentCityName) ||
      isUnresolvedCityId(current.cityId)) {
    return kBrasovCityId;
  }

  try {
    final cities = await ref.read(routeApiRepositoryProvider).getCities();
    final resolved = resolveCatalogCity(
      cities,
      preferredId: currentCityId,
      preferredName: currentCityName,
    );
    return resolved.id;
  } on DioException {
    return currentCityId;
  }
}

bool _useCompanion(String cityId) {
  return cityId == kBrasovCityId ||
      isCityAvailable(cityId: cityId, cityName: kBrasovCityName);
}

final busesProvider = FutureProvider<List<BusLine>>((ref) async {
  ref.watch(searchMapStateProvider.select((s) => s.cityId));
  final cityId = await _resolveCityId(ref);
  if (_useCompanion(cityId)) {
    // Companion city: surface pack errors; do not fall through to empty API.
    return await CompanionCatalog.instance.listBuses();
  }
  // Other cities have no timetables (Timetable shows "not available").
  return const [];
});

final routeStopsProvider = FutureProvider.family<List<RouteStop>,
    ({String routeId, String? directionId})>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  if (!_useCompanion(cityId)) return const [];
  return await CompanionCatalog.instance.routeStops(
    routeId: args.routeId,
    directionId: args.directionId ?? '0',
  );
});

final routeTimetableProvider = FutureProvider.family<
    StopTimetable,
    ({
      String routeId,
      String stopId,
      DateTime serviceDate,
      String? directionId
    })>((ref, args) async {
  final cityId = await _resolveCityId(ref);
  if (!_useCompanion(cityId)) {
    return StopTimetable(
      cityId: cityId,
      routeId: args.routeId,
      stopId: args.stopId,
      serviceDate: CompanionCatalog.isoDate(args.serviceDate),
      departures: const [],
    );
  }
  return await CompanionCatalog.instance.timetable(
    routeId: args.routeId,
    stopId: args.stopId,
    serviceDate: args.serviceDate,
    directionId: args.directionId ?? '0',
  );
});
