import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

/// Fallback when GPS is denied, off, or unavailable (Brașov area; map framing only).
const double kDefaultSearchRefLat = 45.6579;
const double kDefaultSearchRefLon = 25.6012;

const Duration _lastKnownMaxAge = Duration(minutes: 15);
const Duration _mediumFixTimeLimit = Duration(seconds: 10);
const Duration _highFixTimeLimit = Duration(seconds: 18);
const Duration _streamFixTimeLimit = Duration(seconds: 12);

/// Reject fixes worse than this (meters) — coarse / stale readings mislead distance labels.
const double _maxAcceptableAccuracyM = 1200;

/// Whether [position] is recent enough to use without waiting for a new GPS fix.
bool isFreshUserPosition(
  Position position, {
  Duration maxAge = _lastKnownMaxAge,
}) {
  return DateTime.now().difference(position.timestamp) <= maxAge;
}

bool isReliableUserPosition(Position position) {
  final accuracy = position.accuracy;
  if (accuracy.isNaN || accuracy < 0) return true;
  return accuracy <= _maxAcceptableAccuracyM;
}

/// Opens the app settings page so the user can grant location permission.
Future<bool> openUserLocationSettings() => Geolocator.openAppSettings();

/// User-facing hint when [tryGetCurrentUserLatLon] returns null.
Future<({String message, bool showSettingsAction})>
    localizedUserLocationFailure(AppLocalizations l10n) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return (message: l10n.locationServicesOff, showSettingsAction: false);
  }
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.deniedForever) {
    return (
      message: l10n.locationPermissionBlocked,
      showSettingsAction: true,
    );
  }
  if (permission == LocationPermission.denied) {
    return (message: l10n.locationPermissionDenied, showSettingsAction: false);
  }
  if (!kIsWeb && Platform.isIOS) {
    final accuracy = await Geolocator.getLocationAccuracy();
    if (accuracy == LocationAccuracyStatus.reduced) {
      return (
        message: l10n.locationPreciseRequired,
        showSettingsAction: true,
      );
    }
  }
  return (message: l10n.locationGpsFailed, showSettingsAction: false);
}

/// Best-effort current position for ranking/distance; does not throw.
///
/// Does **not** fall back to the city-center default — returns null when GPS fails.
Future<({double lat, double lon, double? accuracyM})?> tryGetCurrentUserLatLon({
  bool forceFresh = false,
}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    if (!kIsWeb && Platform.isIOS) {
      final accuracyStatus = await Geolocator.getLocationAccuracy();
      if (accuracyStatus == LocationAccuracyStatus.reduced) {
        await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'StopDistance',
        );
      }
    }

    if (!forceFresh) {
      final recentLast = await _recentLastKnownPosition();
      if (recentLast != null) {
        return _toFix(recentLast);
      }
    }

    var current = await _tryCurrentPosition(
      accuracy: LocationAccuracy.high,
      timeLimit: _highFixTimeLimit,
    );
    if (current != null) return _toFix(current);

    current = await _tryCurrentPosition(
      accuracy: LocationAccuracy.medium,
      timeLimit: _mediumFixTimeLimit,
    );
    if (current != null) return _toFix(current);

    current = await _firstReliableStreamFix(_streamFixTimeLimit);
    if (current != null) return _toFix(current);

    return null;
  } catch (_) {
    return null;
  }
}

({double lat, double lon, double? accuracyM}) _toFix(Position p) => (
      lat: p.latitude,
      lon: p.longitude,
      accuracyM: p.accuracy,
    );

Future<Position?> _tryCurrentPosition({
  required LocationAccuracy accuracy,
  required Duration timeLimit,
}) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: _platformLocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
    if (!isReliableUserPosition(position)) return null;
    return position;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<Position?> _firstReliableStreamFix(Duration timeout) async {
  final stream = Geolocator.getPositionStream(
    locationSettings: _platformLocationSettings(
      accuracy: LocationAccuracy.high,
    ),
  );
  try {
  await for (final position in stream.timeout(timeout)) {
      if (isReliableUserPosition(position)) return position;
    }
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
  return null;
}

LocationSettings _platformLocationSettings({
  required LocationAccuracy accuracy,
  Duration? timeLimit,
}) {
  if (!kIsWeb && Platform.isAndroid) {
    return AndroidSettings(
      accuracy: accuracy,
      timeLimit: timeLimit,
      distanceFilter: 0,
    );
  }
  if (!kIsWeb && Platform.isIOS) {
    return AppleSettings(
      accuracy: accuracy,
      timeLimit: timeLimit,
      distanceFilter: 0,
    );
  }
  return LocationSettings(
    accuracy: accuracy,
    timeLimit: timeLimit,
    distanceFilter: 0,
  );
}

Future<Position?> _recentLastKnownPosition() async {
  final last = await Geolocator.getLastKnownPosition();
  if (last == null ||
      !isFreshUserPosition(last) ||
      !isReliableUserPosition(last)) {
    return null;
  }
  return last;
}
