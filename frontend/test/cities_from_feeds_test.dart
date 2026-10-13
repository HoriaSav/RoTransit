import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/branding/operator_branding.dart';
import 'package:rotransit/src/core/errors/app_user_message.dart';
import 'package:rotransit/src/features/routes/data/route_api_repository.dart';

void main() {
  group('citiesFromFeeds', () {
    test('maps FeedSummary to CityItem and keeps the Brasov id', () {
      final cities = citiesFromFeeds([
        {'id': 1, 'cityName': 'Brasov', 'companyName': 'RATBV', 'current': null},
        {'id': 2, 'cityName': 'Bucuresti', 'companyName': 'STB'},
      ]);
      expect(cities.map((c) => c.id), [kBrasovCityId, '2']);
      expect(cities.map((c) => c.name), ['Brasov', 'Bucuresti']);
      expect(cities.every((c) => c.country == 'RO'), isTrue);
      expect(isCityAvailable(cityId: cities.first.id, cityName: cities.first.name), isTrue);
    });

    test('deduplicates a city with several feeds and skips bad rows', () {
      final cities = citiesFromFeeds([
        {'id': 5, 'cityName': 'Cluj-Napoca'},
        {'id': 6, 'cityName': 'cluj-napoca'},
        {'id': 7, 'cityName': ''},
        {'cityName': 'Sibiu'},
        'junk',
      ]);
      expect(cities.map((c) => c.id), ['5']);
    });

    test('accepts a wrapped list and tolerates garbage', () {
      expect(citiesFromFeeds({'items': [{'id': 3, 'cityName': 'Iasi'}]}).single.id, '3');
      expect(citiesFromFeeds(null), isEmpty);
    });
  });

  group('backendErrorCode', () {
    test('old code shape still works', () {
      expect(backendErrorCode({'code': 'CITY_NOT_FOUND'}), 'CITY_NOT_FOUND');
    });
    test('ProblemDetail title, detail, status', () {
      expect(backendErrorCode({'title': 'Not Found', 'status': 404, 'detail': 'x'}), 'Not Found');
      expect(backendErrorCode({'detail': 'Feed 9 not found'}), 'Feed 9 not found');
      expect(backendErrorCode({'status': 503}), 'HTTP 503');
      expect(backendErrorCode('nope'), isNull);
    });
    test('a ProblemDetail 404 resolves to the generic unexpected message', () {
      final req = RequestOptions(path: '/api/feeds');
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: req, statusCode: 404,
            data: {'type': 'about:blank', 'title': 'Not Found', 'status': 404}),
      );
      expect(UserMessageResolver.fromError(err), AppUserMessages.unexpectedError);
    });
  });
}
