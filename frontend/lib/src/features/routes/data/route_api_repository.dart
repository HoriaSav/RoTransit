import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/network/api_client.dart';
import '../domain/route_models.dart';

export 'city_catalog.dart';

final routeApiRepositoryProvider = Provider<RouteApiRepository>(
  (ref) => RouteApiRepository(ref.read(dioProvider)),
);

/// City list for the city picker (the only server call the app makes).
class RouteApiRepository {
  RouteApiRepository(this._dio);
  final Dio _dio;

  static const Duration _citiesCacheTtl = Duration(minutes: 5);
  List<CityItem>? _citiesCache;
  DateTime? _citiesCachedAt;
  Future<List<CityItem>>? _citiesInflight;

  Future<List<CityItem>> getCities() async {
    final now = DateTime.now();
    if (_citiesCache != null &&
        _citiesCachedAt != null &&
        now.difference(_citiesCachedAt!) < _citiesCacheTtl) {
      return _citiesCache!;
    }
    if (_citiesInflight != null) {
      return _citiesInflight!;
    }
    _citiesInflight = _fetchCitiesFromNetwork().then((list) {
      _citiesCache = list;
      _citiesCachedAt = DateTime.now();
      return list;
    }).whenComplete(() {
      _citiesInflight = null;
    });
    return _citiesInflight!;
  }

  Future<List<CityItem>> _fetchCitiesFromNetwork() async {
    final response = await _dio.get('/api/feeds');
    return citiesFromFeeds(response.data);
  }
}

/// Maps the backend_v2 `GET /api/feeds` list (FeedSummary) to picker cities.
///
/// The id is the feed id as a string, except Brasov, which keeps
/// [kBrasovCityId] so the bundled companion pack and saved state still match.
/// A city with several feeds appears once (first feed wins).
List<CityItem> citiesFromFeeds(Object? raw) {
  final List<dynamic> items;
  if (raw is List<dynamic>) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    final nested = raw['items'] ?? raw['content'] ?? raw['data'] ?? const [];
    items = nested is List<dynamic> ? nested : const [];
  } else {
    items = const [];
  }
  final seen = <String>{};
  final cities = <CityItem>[];
  for (final feed in items.whereType<Map<String, dynamic>>()) {
    final feedId = (feed['id'] ?? '').toString().trim();
    final name = (feed['cityName'] ?? '').toString().trim();
    if (feedId.isEmpty || name.isEmpty) continue;
    if (!seen.add(name.toLowerCase())) continue;
    final isBrasov = isCityAvailable(cityId: '', cityName: name);
    cities.add(CityItem(
      id: isBrasov ? kBrasovCityId : feedId,
      name: name,
      country: 'RO',
    ));
  }
  return cities;
}
