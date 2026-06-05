import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'user_location_helpers.dart';

/// Cached device location shared across search, station picker, and map.
class UserLocationState {
  const UserLocationState({
    this.lat,
    this.lon,
    this.accuracyM,
    this.isResolving = false,
    this.resolveFinished = false,
  });

  final double? lat;
  final double? lon;
  final double? accuracyM;
  final bool isResolving;
  final bool resolveFinished;

  bool get hasFix => lat != null && lon != null;

  UserLocationState copyWith({
    double? lat,
    double? lon,
    double? accuracyM,
    bool? isResolving,
    bool? resolveFinished,
    bool clearFix = false,
  }) {
    return UserLocationState(
      lat: clearFix ? null : (lat ?? this.lat),
      lon: clearFix ? null : (lon ?? this.lon),
      accuracyM: clearFix ? null : (accuracyM ?? this.accuracyM),
      isResolving: isResolving ?? this.isResolving,
      resolveFinished: resolveFinished ?? this.resolveFinished,
    );
  }
}

class UserLocationNotifier extends StateNotifier<UserLocationState> {
  UserLocationNotifier() : super(const UserLocationState());

  Future<UserLocationState> resolve({bool forceFresh = false}) async {
    state = state.copyWith(isResolving: true, resolveFinished: false);
    final fix = await tryGetCurrentUserLatLon(forceFresh: forceFresh);
    state = UserLocationState(
      lat: fix?.lat,
      lon: fix?.lon,
      accuracyM: fix?.accuracyM,
      isResolving: false,
      resolveFinished: true,
    );
    return state;
  }
}

final userLocationProvider =
    StateNotifierProvider<UserLocationNotifier, UserLocationState>(
  (ref) => UserLocationNotifier(),
);
