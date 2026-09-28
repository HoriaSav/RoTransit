import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final response = await _dio.get('/api/cities');
    final raw = response.data;
    final List<dynamic> items;
    if (raw is List<dynamic>) {
      items = raw;
    } else if (raw is Map<String, dynamic>) {
      final nested = raw['items'] ?? raw['content'] ?? raw['data'] ?? const [];
      items = nested is List<dynamic> ? nested : const [];
    } else {
      items = const [];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(CityItem.fromJson)
        .where((c) => c.id.isNotEmpty)
        .toList();
  }
}
