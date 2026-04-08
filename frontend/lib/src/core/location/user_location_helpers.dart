import 'package:geolocator/geolocator.dart';

/// Fallback when GPS is denied, off, or unavailable (Brașov area; used for search/map).
const double kDefaultSearchRefLat = 45.6579;
const double kDefaultSearchRefLon = 25.6012;

/// Best-effort current position for ranking/distance; does not throw.
Future<({double lat, double lon})?> tryGetCurrentUserLatLon() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return (lat: position.latitude, lon: position.longitude);
  } catch (_) {
    return null;
  }
}
