import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/domain/route_models.dart';

void main() {
  test('route metadata roundtrip is stable', () {
    const route = RouteOption(
      durationSeconds: 600,
      transfers: 1,
      walkDistanceMeters: 320,
      legs: [
        RouteLeg(
          mode: 'WALK',
          routeId: '',
          fromName: 'A',
          fromLat: 0,
          fromLon: 0,
          toName: 'B',
          toLat: 0,
          toLon: 0,
          startTime: 1,
          endTime: 2,
          distance: 100,
        ),
      ],
    );

    final metadata = encodeRouteMetadata(route);
    final decoded = decodeRouteMetadata(metadata);

    expect(decoded.durationSeconds, route.durationSeconds);
    expect(decoded.legs.first.mode, 'WALK');
  });
}
