import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/connectivity_status.dart';
import '../domain/route_models.dart';
import 'offline_transit_cache_repository.dart';

export 'city_catalog.dart';

final routeApiRepositoryProvider = Provider<RouteApiRepository>(
  (ref) => RouteApiRepository(
    ref.read(dioProvider),
    ref.read(offlineTransitCacheRepositoryProvider),
  ),
);

class RouteApiRepository {
  RouteApiRepository(this._dio, this._offlineTransitCache);
  final Dio _dio;
  final OfflineTransitCacheRepository _offlineTransitCache;

  static const Duration _nearbyStopsCacheTtl = Duration(minutes: 3);
  final Map<String, ({List<NearbyStopItem> items, DateTime storedAt})>
      _nearbyStopsCache = {};
  final Map<String, Future<OfflinePackMeta>> _offlinePackMetaInflight = {};

  static const Duration _citiesCacheTtl = Duration(minutes: 5);
  List<CityItem>? _citiesCache;
  DateTime? _citiesCachedAt;
  Future<List<CityItem>>? _citiesInflight;

  String _nearbyStopsCacheKey(
    String cityId,
    double lat,
    double lon,
    int radiusMeters,
  ) {
    return '${cityId}_${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}_$radiusMeters';
  }

  Future<bool> _hasOfflinePack(String cityId) async {
    if (cityId.isEmpty) return false;
    final meta = await _offlineTransitCache.getMetaForCity(cityId);
    return meta != null;
  }

  Future<RouteSearchResponse> search(RouteSearchRequest request) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/routes/search',
      queryParameters: {
        'cityId': request.cityId,
        'origin': request.origin,
        'destination': request.destination,
        'serviceDate': DateFormat('yyyy-MM-dd').format(request.serviceDate),
        'serviceTime': DateFormat('HH:mm:ss').format(request.serviceTime),
        'passengerCount': request.passengerCount,
        'offset': request.offset,
        'limit': request.limit,
        'includeGeometry': request.includeGeometry,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final routes = (data['routes'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => RouteOption.fromJson(e as Map<String, dynamic>))
        .toList();
    return RouteSearchResponse(
      cityId: data['cityId'] as String? ?? request.cityId,
      cityName: data['cityName'] as String? ?? 'Brasov',
      offset: (data['offset'] as num?)?.toInt() ?? request.offset,
      limit: (data['limit'] as num?)?.toInt() ?? request.limit,
      total: (data['total'] as num?)?.toInt() ?? routes.length,
      hasMore: data['hasMore'] as bool? ??
          ((data['total'] as num?)?.toInt() ?? routes.length) >
              ((data['offset'] as num?)?.toInt() ?? request.offset) +
                  routes.length,
      routes: routes,
    );
  }

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

  Future<List<NearbyStopItem>> getNearbyStops({
    required String cityId,
    required double lat,
    required double lon,
    int radiusMeters = 5000,
  }) async {
    final cacheKey = _nearbyStopsCacheKey(cityId, lat, lon, radiusMeters);
    final entry = _nearbyStopsCache[cacheKey];
    if (entry != null &&
        DateTime.now().difference(entry.storedAt) < _nearbyStopsCacheTtl) {
      return entry.items;
    }
    final response = await _dio.get<List<dynamic>>(
      '/api/stops/nearby',
      queryParameters: {
        'cityId': cityId,
        'lat': lat,
        'lon': lon,
        'radiusMeters': radiusMeters,
      },
    );
    final data = response.data ?? <dynamic>[];
    final items = data
        .map((e) => NearbyStopItem.fromJson(e as Map<String, dynamic>))
        .where((s) => s.name.isNotEmpty)
        .toList();
    _nearbyStopsCache[cacheKey] = (items: items, storedAt: DateTime.now());
    return items;
  }

  Future<List<StopSearchItem>> searchStops({
    required String cityId,
    required String query,
    int limit = 10,
    double? refLat,
    double? refLon,
  }) async {
    final queryParameters = <String, dynamic>{
      'cityId': cityId,
      'q': query,
      'limit': limit,
    };
    if (refLat != null && refLon != null) {
      queryParameters['refLat'] = refLat;
      queryParameters['refLon'] = refLon;
    }
    final response = await _dio.get<List<dynamic>>(
      '/api/stops/search',
      queryParameters: queryParameters,
    );
    final data = response.data ?? <dynamic>[];
    return data
        .map((e) => StopSearchItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// When several GTFS stops share the same name, asks the backend to pick the destination
  /// that yields the best OTP itinerary from [origin] (fewer transfers, then time, then walk).
  Future<String> resolveDestinationForRoute({
    required String cityId,
    required String origin,
    required String stopName,
    required DateTime serviceDateTime,
    double? fallbackLat,
    double? fallbackLon,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/stops/resolve-for-route',
        queryParameters: {
          'cityId': cityId,
          'origin': origin,
          'stopName': stopName,
          'serviceDate': DateFormat('yyyy-MM-dd').format(serviceDateTime),
          'serviceTime': DateFormat('HH:mm:ss').format(serviceDateTime),
        },
      );
      final data = response.data ?? <String, dynamic>{};
      final lat = (data['lat'] as num?)?.toDouble();
      final lon = (data['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        return '$lat,$lon';
      }
    } on DioException catch (_) {
      // Offline / 404 / gateway: keep UX usable with the suggestion coordinates.
    }
    if (fallbackLat != null && fallbackLon != null) {
      return '$fallbackLat,$fallbackLon';
    }
    return origin;
  }

  Future<List<BusLine>> listBuses({required String cityId}) async {
    Future<List<BusLine>> fromCache() async {
      final cached = await _offlineTransitCache.getBuses(cityId);
      return cached ?? <BusLine>[];
    }
    if (await _hasOfflinePack(cityId)) {
      return fromCache();
    }
    if (!await isDeviceOnline()) {
      return fromCache();
    }
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/buses',
        queryParameters: {'cityId': cityId},
      );
      final data = response.data ?? <dynamic>[];
      return data
          .map((e) => BusLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return fromCache();
    }
  }

  Future<List<RouteStop>> getRouteStops({
    required String cityId,
    required String routeId,
    String? directionId,
  }) async {
    Future<List<RouteStop>> fromCache() async {
      final cached = await _offlineTransitCache.getRouteStops(
        cityId: cityId,
        routeId: routeId,
        directionId: directionId,
      );
      return cached ?? <RouteStop>[];
    }
    if (await _hasOfflinePack(cityId)) {
      return fromCache();
    }
    if (!await isDeviceOnline()) {
      return fromCache();
    }
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/buses/$routeId/stops',
        queryParameters: {
          'cityId': cityId,
          if (directionId != null && directionId.isNotEmpty)
            'directionId': directionId,
        },
      );
      final data = response.data ?? <dynamic>[];
      return data
          .map((e) => RouteStop.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return fromCache();
    }
  }

  Future<StopTimetable> getTimetable({
    required String cityId,
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? directionId,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(serviceDate);
    StopTimetable emptyForDate() => StopTimetable(
          cityId: cityId,
          routeId: routeId,
          stopId: stopId,
          serviceDate: dateStr,
          departures: const [],
        );
    Future<StopTimetable> fromCache() async {
      final cached = await _offlineTransitCache.getTimetable(
        cityId: cityId,
        routeId: routeId,
        stopId: stopId,
        serviceDate: serviceDate,
        directionId: directionId,
      );
      return cached ?? emptyForDate();
    }
    if (await _hasOfflinePack(cityId)) {
      return fromCache();
    }
    if (!await isDeviceOnline()) {
      return fromCache();
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/buses/$routeId/timetable',
        queryParameters: {
          'cityId': cityId,
          'stopId': stopId,
          'serviceDate': dateStr,
          if (directionId != null && directionId.isNotEmpty)
            'directionId': directionId,
        },
      );
      return StopTimetable.fromJson(response.data ?? <String, dynamic>{});
    } on DioException catch (_) {
      return fromCache();
    }
  }

  Future<OfflinePackMeta> fetchOfflinePackMeta({
    required String cityId,
    required DateTime anchorMonday,
  }) async {
    final anchor = DateFormat('yyyy-MM-dd').format(anchorMonday);
    final key = '$cityId|$anchor';
    return _offlinePackMetaInflight.putIfAbsent(key, () {
      return _fetchOfflinePackMetaOnce(
        cityId: cityId,
        anchorMondayStr: anchor,
      ).whenComplete(() => _offlinePackMetaInflight.remove(key));
    });
  }

  Future<OfflinePackMeta> _fetchOfflinePackMetaOnce({
    required String cityId,
    required String anchorMondayStr,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/buses/offline-pack-meta',
        queryParameters: {'cityId': cityId, 'anchorMonday': anchorMondayStr},
      );
      final data = response.data ?? <String, dynamic>{};
      return OfflinePackMeta(
        cityId: (data['cityId'] ?? '').toString(),
        anchorMonday: (data['anchorMonday'] ?? '').toString(),
        packVersion: (data['packVersion'] ?? '').toString(),
        generatedAt: (data['generatedAt'] ?? '').toString(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return OfflinePackMeta(
          cityId: cityId,
          anchorMonday: anchorMondayStr,
          packVersion: '',
          generatedAt: '',
          endpointMissing: true,
        );
      }
      rethrow;
    }
  }

  /// Fetches the offline catalog pack and replaces the on-device SQLite snapshot for [cityId].
  Future<void> downloadOfflineTransitPack({
    required String cityId,
    required DateTime anchorMonday,
    void Function(int received, int total)? onProgress,
    VoidCallback? onSavingStarted,
  }) async {
    final anchor = DateFormat('yyyy-MM-dd').format(anchorMonday);
    final response = await _dio.get<ResponseBody>(
      '/api/buses/offline-pack',
      queryParameters: {'cityId': cityId, 'anchorMonday': anchor},
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final body = response.data;
    if (body == null) {
      throw StateError('Empty offline-pack response');
    }

    final totalHeader = response.headers.value('content-length');
    final parsedTotal = int.tryParse(totalHeader ?? '');
    final totalBytes = parsedTotal != null && parsedTotal > 0 ? parsedTotal : -1;
    onProgress?.call(0, totalBytes);

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in body.stream) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(received, totalBytes);
    }

    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw StateError('Empty offline-pack response');
    }
    onSavingStarted?.call();
    final raw = utf8.decode(bytes);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    await _offlineTransitCache.applyOfflinePackJson(
      decoded,
      expectedCityId: cityId,
    );
  }
}

class OfflinePackMeta {
  const OfflinePackMeta({
    required this.cityId,
    required this.anchorMonday,
    required this.packVersion,
    required this.generatedAt,
    this.endpointMissing = false,
  });

  final String cityId;
  final String anchorMonday;
  final String packVersion;
  final String generatedAt;

  /// True when the server responded 404 for [offline-pack-meta] (older deployments).
  final bool endpointMissing;
}
