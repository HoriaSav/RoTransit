import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/domain/route_models.dart';
import 'package:rotransit_frontend/src/features/shell/state/navigation_provider.dart';

void main() {
  test('search map controller paginates in chunks of 10', () {
    final controller = SearchMapController();
    final firstPage = List.generate(
      10,
      (_) => const RouteOption(
        durationSeconds: 100,
        transfers: 0,
        walkDistanceMeters: 50,
        legs: [],
      ),
    );
    final request = RouteSearchRequest(
      cityId: '1',
      origin: 'A',
      destination: 'B',
      serviceDate: DateTime(2026, 1, 1),
      serviceTime: DateTime(2026, 1, 1, 8, 0),
    );
    controller.setResults(
      cityId: '1',
      cityName: 'Brasov',
      options: firstPage,
      offset: 0,
      limit: 10,
      total: 25,
      request: request,
    );
    expect(controller.state.visibleCount, 10);
    expect(controller.hasMore, isTrue);
    final secondPage = List.generate(
      10,
      (_) => const RouteOption(
        durationSeconds: 110,
        transfers: 0,
        walkDistanceMeters: 60,
        legs: [],
      ),
    );
    controller.appendResults(
        options: secondPage, offset: 10, limit: 10, total: 25);
    expect(controller.state.visibleCount, 20);
    controller.appendResults(
      options: const [
        RouteOption(
            durationSeconds: 120,
            transfers: 0,
            walkDistanceMeters: 70,
            legs: []),
        RouteOption(
            durationSeconds: 120,
            transfers: 0,
            walkDistanceMeters: 70,
            legs: []),
        RouteOption(
            durationSeconds: 120,
            transfers: 0,
            walkDistanceMeters: 70,
            legs: []),
        RouteOption(
            durationSeconds: 120,
            transfers: 0,
            walkDistanceMeters: 70,
            legs: []),
        RouteOption(
            durationSeconds: 120,
            transfers: 0,
            walkDistanceMeters: 70,
            legs: []),
      ],
      offset: 20,
      limit: 10,
      total: 25,
    );
    expect(controller.state.visibleCount, 25);
    expect(controller.hasMore, isFalse);
  });
}
