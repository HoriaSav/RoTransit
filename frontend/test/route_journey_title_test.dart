import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/domain/route_models.dart';

RouteOption _walkTransitWalkRoute() {
  return const RouteOption(
    durationSeconds: 900,
    transfers: 0,
    walkDistanceMeters: 200,
    legs: [
      RouteLeg(
        mode: 'WALK',
        routeId: '',
        fromName: 'Origin',
        fromLat: 45.6,
        fromLon: 25.6,
        toName: 'Livada Postei',
        toLat: 45.61,
        toLon: 25.61,
        startTime: 1,
        endTime: 2,
        distance: 80,
      ),
      RouteLeg(
        mode: 'BUS',
        routeId: '5',
        fromName: 'Livada Postei',
        fromLat: 45.61,
        fromLon: 25.61,
        toName: 'Gara',
        toLat: 45.65,
        toLon: 25.65,
        startTime: 2,
        endTime: 3,
        distance: 1200,
      ),
      RouteLeg(
        mode: 'WALK',
        routeId: '',
        fromName: 'Gara',
        fromLat: 45.65,
        fromLon: 25.65,
        toName: 'Destination',
        toLat: 45.66,
        toLon: 25.66,
        startTime: 3,
        endTime: 4,
        distance: 60,
      ),
    ],
  );
}

void main() {
  test('routeJourneyTitle skips generic walk endpoints', () {
    final route = _walkTransitWalkRoute();
    expect(routeJourneyTitle(route), 'Livada Postei – Gara');
  });

  test('routeJourneyTitle prefers explicit search labels', () {
    final route = _walkTransitWalkRoute();
    expect(
      routeJourneyTitle(
        route,
        originLabel: 'Piata Sfatului',
        destinationLabel: 'Gara Brasov',
      ),
      'Piata Sfatului – Gara Brasov',
    );
  });

  test('routeOptionWithJourneyLabels patches metadata endpoints', () {
    final route = _walkTransitWalkRoute();
    final patched = routeOptionWithJourneyLabels(
      route,
      originLabel: 'Piata Sfatului',
      destinationLabel: 'Gara Brasov',
    );
    expect(patched.legs.first.fromName, 'Piata Sfatului');
    expect(patched.legs.last.toName, 'Gara Brasov');
    expect(
      routeJourneyTitle(
        patched,
        originLabel: 'Piata Sfatului',
        destinationLabel: 'Gara Brasov',
      ),
      'Piata Sfatului – Gara Brasov',
    );
  });

  test('savedJourneyTitle falls back when label is generic', () {
    final route = _walkTransitWalkRoute();
    expect(
      savedJourneyTitle(label: 'Origin – Destination', route: route),
      'Livada Postei – Gara',
    );
  });
}
