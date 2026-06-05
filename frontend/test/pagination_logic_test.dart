import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/domain/route_models.dart';
import 'package:rotransit_frontend/src/features/shell/state/navigation_provider.dart';

void main() {
  test('search map controller reveals results in chunks of kRouteSearchPageSize', () {
    expect(kRouteSearchPageSize, 5);
    final controller = SearchMapController();
    RouteOption opt(int sec) => RouteOption(
          durationSeconds: sec,
          transfers: 0,
          walkDistanceMeters: 50,
          legs: const [],
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
      options: List.generate(25, (i) => opt(100 + i)),
      offset: 0,
      limit: kRouteSearchPageSize,
      total: 25,
      hasMore: false,
      request: request,
    );
    expect(controller.state.visibleCount, 5);
    expect(controller.canLoadMore, isTrue);

    controller.revealMoreResults();
    expect(controller.state.visibleCount, 10);
    expect(controller.canLoadMore, isTrue);

    controller.revealMoreResults();
    expect(controller.state.visibleCount, 15);
    expect(controller.canLoadMore, isTrue);

    controller.revealMoreResults();
    expect(controller.state.visibleCount, 20);
    expect(controller.canLoadMore, isTrue);

    controller.revealMoreResults();
    expect(controller.state.visibleCount, 25);
    expect(controller.canLoadMore, isFalse);
  });

  test('appendResults extends list and reveals next page chunk', () {
    final controller = SearchMapController();
    RouteOption opt(int sec) => RouteOption(
          durationSeconds: sec,
          transfers: 0,
          walkDistanceMeters: 50,
          legs: const [],
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
      options: List.generate(5, (i) => opt(100 + i)),
      offset: 0,
      limit: kRouteSearchPageSize,
      total: 12,
      hasMore: true,
      request: request,
    );
    expect(controller.state.results.length, 5);
    expect(controller.state.visibleCount, 5);

    controller.appendResults(
      options: List.generate(5, (i) => opt(200 + i)),
      offset: 5,
      limit: kRouteSearchPageSize,
      total: 12,
      hasMore: true,
    );
    expect(controller.state.results.length, 10);
    expect(controller.state.visibleCount, 10);
    expect(controller.state.offset, 5);
    expect(controller.state.total, 12);
    expect(controller.state.hasMore, isTrue);
    expect(controller.canLoadMore, isTrue);
  });

  test('canLoadMore when server hasMore with all results visible', () {
    final controller = SearchMapController();
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
      options: List.generate(3, (i) => RouteOption(
            durationSeconds: 100 + i,
            transfers: 0,
            walkDistanceMeters: 50,
            legs: const [],
          )),
      offset: 0,
      limit: kRouteSearchPageSize,
      total: 3,
      hasMore: true,
      request: request,
    );
    expect(controller.state.visibleCount, 3);
    expect(controller.canLoadMore, isTrue);
  });
}
