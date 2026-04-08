import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_saved_routes_repository.dart';
import 'route_api_repository.dart';

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.read(localSavedRoutesRepositoryProvider),
    ref.read(routeApiRepositoryProvider),
  ),
);

class SyncService {
  SyncService(this._localRepo, this._apiRepo);

  final LocalSavedRoutesRepository _localRepo;
  final RouteApiRepository _apiRepo;

  Future<void> syncPending() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    final pending = await _localRepo.pendingSyncSaves();
    for (final item in pending) {
      final payload =
          jsonDecode(item['payload'] as String) as Map<String, dynamic>;
      await _apiRepo.saveRoute(
        deviceUserId: payload['deviceUserId'] as String,
        cityId: payload['cityId'] as String,
        routeMetadata: payload['routeMetadata'] as String,
        label: payload['label'] as String?,
      );
      await _localRepo.removeSyncItem(item['id'] as int);
    }
  }
}
