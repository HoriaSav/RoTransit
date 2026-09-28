import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rotransit/src/core/location/user_location_helpers.dart';

Position _position({
  required double lat,
  required double lon,
  double accuracy = 12,
  DateTime? timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  test('isUsableLatLon rejects NaN, inf, out of range, and 0,0', () {
    expect(isUsableLatLon(45.65, 25.61), isTrue);
    expect(isUsableLatLon(double.nan, 25.61), isFalse);
    expect(isUsableLatLon(45.65, double.infinity), isFalse);
    expect(isUsableLatLon(91, 25.61), isFalse);
    expect(isUsableLatLon(45.65, 181), isFalse);
    expect(isUsableLatLon(0, 0), isFalse);
  });

  test('isReliableUserPosition requires usable coordinates', () {
    expect(isReliableUserPosition(_position(lat: 45.65, lon: 25.61)), isTrue);
    expect(isReliableUserPosition(_position(lat: 0, lon: 0, accuracy: 5)), isFalse);
    expect(
      isReliableUserPosition(_position(lat: 45.65, lon: 25.61, accuracy: 2000)),
      isFalse,
    );
  });

  test('isFreshUserPosition uses the timestamp age', () {
    expect(
      isFreshUserPosition(
        _position(
          lat: 45.65,
          lon: 25.61,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ),
      isTrue,
    );
    expect(
      isFreshUserPosition(
        _position(
          lat: 45.65,
          lon: 25.61,
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ),
      isFalse,
    );
  });
}
