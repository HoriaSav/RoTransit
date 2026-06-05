import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/core/format/distance_format.dart';

void main() {
  group('formatDistanceForDisplay', () {
    test('shows meters up to 100', () {
      expect(formatDistanceForDisplay(0), '0 m');
      expect(formatDistanceForDisplay(50), '50 m');
      expect(formatDistanceForDisplay(100), '100 m');
    });

    test('shows km with one decimal above 100m', () {
      expect(formatDistanceForDisplay(101), '0.1 km');
      expect(formatDistanceForDisplay(1234), '1.2 km');
      expect(formatDistanceForDisplay(10000), '10.0 km');
    });
  });

  group('formatDistanceAwayFromUser', () {
    test('appends away from you', () {
      expect(formatDistanceAwayFromUser(400), '0.4 km away from you');
      expect(formatDistanceAwayFromUser(80), '80 m away from you');
    });
  });
}
