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

  bool get hasFix {
    final la = lat;
    final lo = lon;
    return la != null && lo != null && isUsableLatLon(la, lo);
  }

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

  Future<UserLocationState>? _inFlight;

  /// One GPS/permission attempt at a time (the map's "center on me" tap);
  /// overlapping [Geolocator] requests can crash.
  Future<UserLocationState> resolve({bool forceFresh = false}) {
    return _inFlight ??= _doResolve(forceFresh: forceFresh).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<UserLocationState> _doResolve({required bool forceFresh}) async {
    final previous = state;
    state = state.copyWith(isResolving: true, resolveFinished: false);
    final fix = await tryGetCurrentUserLatLon(forceFresh: forceFresh);
    if (fix == null) {
      state = UserLocationState(
        lat: previous.lat,
        lon: previous.lon,
        accuracyM: previous.accuracyM,
        isResolving: false,
        resolveFinished: true,
      );
      return state;
    }
    state = UserLocationState(
      lat: fix.lat,
      lon: fix.lon,
      accuracyM: fix.accuracyM,
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
