import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

typedef LivePosition = ({double lat, double lon});

/// Live device position for the map's blue dot. A provider so tests can
/// replace Geolocator with a fake.
abstract class LivePositionSource {
  /// True when location permission is already granted (never prompts).
  Future<bool> canFollow();

  /// Position updates; listen only while the map is visible.
  Stream<LivePosition> positions();
}

class GeolocatorPositionSource implements LivePositionSource {
  const GeolocatorPositionSource();

  /// Minimum movement (metres) before a new position is delivered.
  static const distanceFilterM = 15;

  @override
  Future<bool> canFollow() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<LivePosition> positions() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterM,
      ),
    ).map((p) => (lat: p.latitude, lon: p.longitude));
  }
}

final livePositionSourceProvider = Provider<LivePositionSource>(
  (ref) => const GeolocatorPositionSource(),
);
