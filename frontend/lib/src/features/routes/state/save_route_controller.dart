import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../../saved/state/saved_providers.dart';
import '../data/local_saved_routes_repository.dart';
import '../data/route_api_repository.dart';
import '../data/sync_service.dart';
import '../domain/route_models.dart';

final saveRouteControllerProvider = Provider<SaveRouteController>(
  (ref) => SaveRouteController(ref),
);

const _guestDeviceUserId = 'guest-local-user';

class SaveRouteController {
  SaveRouteController(this._ref);
  final Ref _ref;

  Future<void> save({
    required String cityId,
    required RouteOption option,
    String? label,
    String? originLabel,
    String? destinationLabel,
  }) async {
    final user = _ref.read(sessionProvider);
    final deviceUserId = user?.id ?? _guestDeviceUserId;
    final normalized = routeOptionWithJourneyLabels(
      option,
      originLabel: originLabel,
      destinationLabel: destinationLabel,
    );
    final resolvedLabel = label ??
        routeJourneyTitle(
          normalized,
          originLabel: originLabel,
          destinationLabel: destinationLabel,
        );

    final metadata = encodeRouteMetadata(normalized);
    await _ref.read(localSavedRoutesRepositoryProvider).save(
          deviceUserId: deviceUserId,
          cityId: cityId,
          routeMetadata: metadata,
          label: resolvedLabel,
        );
    _ref.invalidate(savedJourneysProvider);

    // In guest/bypassed-auth mode we persist locally only.
    if (user == null) return;

    final payload = <String, dynamic>{
      'deviceUserId': deviceUserId,
      'cityId': cityId,
      'routeMetadata': metadata,
      'label': resolvedLabel,
    };

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      await _ref
          .read(localSavedRoutesRepositoryProvider)
          .enqueueSaveSync(payload);
      return;
    }

    try {
      await _ref.read(routeApiRepositoryProvider).saveRoute(
            deviceUserId: deviceUserId,
            cityId: cityId,
            routeMetadata: metadata,
            label: resolvedLabel,
          );
    } catch (_) {
      await _ref
          .read(localSavedRoutesRepositoryProvider)
          .enqueueSaveSync(payload);
    }

    await _ref.read(syncServiceProvider).syncPending();
    _ref.invalidate(savedJourneysProvider);
  }
}
