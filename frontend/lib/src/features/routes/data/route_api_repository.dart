import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/route_models.dart';
import 'stop_suggestion_dedupe.dart';

final routeApiRepositoryProvider = Provider<RouteApiRepository>(
  (ref) => RouteApiRepository(ref.read(dioProvider)),
);

class RouteApiRepository {
  RouteApiRepository(this._dio);
  final Dio _dio;

  Future<RouteSearchResponse> search(RouteSearchRequest request) async {
    if (!ApiConfig.useBackend) {
      return _mockSearchResponse(request);
    }
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
      routes: routes,
    );
  }

  Future<List<CityItem>> getCities() async {
    if (!ApiConfig.useBackend) {
      return const [
        CityItem(
          id: '00000000-0000-0000-0000-000000000001',
          name: 'Preview City',
          country: 'RO',
        ),
      ];
    }
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
    if (!ApiConfig.useBackend) {
      const mock = [
        NearbyStopItem(
          stopId: 'preview-1a',
          name: 'Rulmentul',
          lat: 45.6618,
          lon: 25.6224,
        ),
        NearbyStopItem(
          stopId: 'preview-1b',
          name: 'Rulmentul',
          lat: 45.66185,
          lon: 25.62245,
        ),
        NearbyStopItem(
          stopId: 'preview-2',
          name: 'Gara Brasov',
          lat: 45.6507,
          lon: 25.6067,
        ),
        NearbyStopItem(
          stopId: 'preview-3',
          name: 'Livada Postei',
          lat: 45.6449,
          lon: 25.5887,
        ),
        NearbyStopItem(
          stopId: 'preview-4',
          name: 'Coresi',
          lat: 45.6758,
          lon: 25.6108,
        ),
      ];
      return dedupeNearbyStopItems(
        mock,
        mock.length,
        refLat: lat,
        refLon: lon,
      );
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
    return data
        .map((e) => NearbyStopItem.fromJson(e as Map<String, dynamic>))
        .where((s) => s.name.isNotEmpty)
        .toList();
  }

  Future<List<StopSearchItem>> searchStops({
    required String cityId,
    required String query,
    int limit = 10,
    double? refLat,
    double? refLon,
  }) async {
    if (!ApiConfig.useBackend) {
      const mock = [
        StopSearchItem(
          stopId: 'preview-1a',
          name: 'Rulmentul',
          lat: 45.6618,
          lon: 25.6224,
        ),
        StopSearchItem(
          stopId: 'preview-1b',
          name: 'Rulmentul',
          lat: 45.66185,
          lon: 25.62245,
        ),
        StopSearchItem(
          stopId: 'preview-2',
          name: 'Gara Brasov',
          lat: 45.6507,
          lon: 25.6067,
        ),
        StopSearchItem(
          stopId: 'preview-3',
          name: 'Livada Postei',
          lat: 45.6449,
          lon: 25.5887,
        ),
      ];
      final q = query.toLowerCase();
      final filtered =
          mock.where((s) => s.name.toLowerCase().contains(q)).toList();
      return dedupeStopSearchItems(
        filtered,
        limit,
        refLat: refLat,
        refLon: refLon,
      );
    }
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
    if (!ApiConfig.useBackend) {
      if (fallbackLat != null && fallbackLon != null) {
        return '$fallbackLat,$fallbackLon';
      }
      return origin;
    }
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
    if (!ApiConfig.useBackend) {
      return const [
        BusLine(
            routeId: 'ROUTE:61',
            shortName: '61',
            longName: 'Center - Rulmentul',
            mode: 'BUS'),
        BusLine(
            routeId: 'ROUTE:17',
            shortName: '17',
            longName: 'Gara - Coresi',
            mode: 'BUS'),
      ];
    }
    final response = await _dio.get<List<dynamic>>(
      '/api/buses',
      queryParameters: {'cityId': cityId},
    );
    final data = response.data ?? <dynamic>[];
    return data
        .map((e) => BusLine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteStop>> getRouteStops({
    required String cityId,
    required String routeId,
    String? directionId,
  }) async {
    if (!ApiConfig.useBackend) {
      return const [
        RouteStop(
            stopId: 'STOP:1',
            name: 'Gara Brasov',
            lat: 45.6507,
            lon: 25.6067,
            stopSequence: 1),
        RouteStop(
            stopId: 'STOP:2',
            name: 'Onix',
            lat: 45.6541,
            lon: 25.6001,
            stopSequence: 2),
        RouteStop(
            stopId: 'STOP:3',
            name: 'Rulmentul',
            lat: 45.6618,
            lon: 25.6224,
            stopSequence: 3),
      ];
    }
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
  }

  Future<StopTimetable> getTimetable({
    required String cityId,
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? directionId,
  }) async {
    if (!ApiConfig.useBackend) {
      return const StopTimetable(
        cityId: 'preview',
        routeId: 'ROUTE:61',
        stopId: 'STOP:1',
        serviceDate: '2026-04-01',
        departures: [
          StopTimetableEntry(
              tripId: 'TRIP:1', headsign: 'Center', departureTime: '08:10:00'),
          StopTimetableEntry(
              tripId: 'TRIP:2', headsign: 'Center', departureTime: '08:25:00'),
          StopTimetableEntry(
              tripId: 'TRIP:3', headsign: 'Center', departureTime: '08:40:00'),
        ],
      );
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/buses/$routeId/timetable',
      queryParameters: {
        'cityId': cityId,
        'stopId': stopId,
        'serviceDate': DateFormat('yyyy-MM-dd').format(serviceDate),
        if (directionId != null && directionId.isNotEmpty)
          'directionId': directionId,
      },
    );
    return StopTimetable.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<SavedRouteValidation> validateSavedRoute({
    required String routeId,
    required String deviceUserId,
    required DateTime serviceDateTime,
  }) async {
    if (!ApiConfig.useBackend) {
      return const SavedRouteValidation(isValid: true, reason: 'PREVIEW_MODE');
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/routes/saved/$routeId/validate',
      queryParameters: {
        'deviceUserId': deviceUserId,
        'serviceDate': DateFormat('yyyy-MM-dd').format(serviceDateTime),
        'serviceTime': DateFormat('HH:mm:ss').format(serviceDateTime),
      },
    );
    return SavedRouteValidation.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<List<SavedRouteItem>> getSavedRoutes({
    required String deviceUserId,
    String? cityId,
  }) async {
    if (!ApiConfig.useBackend) return const [];
    final response = await _dio.get<List<dynamic>>(
      '/api/routes/saved',
      queryParameters: {
        'deviceUserId': deviceUserId,
        if (cityId != null && cityId.isNotEmpty) 'cityId': cityId,
      },
    );
    final data = response.data ?? <dynamic>[];
    return data
        .map((e) => SavedRouteItem.fromJson(e as Map<String, dynamic>))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<void> saveRoute({
    required String deviceUserId,
    required String cityId,
    required String routeMetadata,
    String? label,
  }) async {
    if (!ApiConfig.useBackend) return;
    await _dio.post(
      '/api/routes/save',
      data: {
        'deviceUserId': deviceUserId,
        'cityId': cityId,
        'label': label ?? 'Saved journey',
        'routeMetadata': routeMetadata,
      },
    );
  }

  RouteSearchResponse _mockSearchResponse(RouteSearchRequest request) {
    final base = request.serviceTime.millisecondsSinceEpoch;
    RouteLeg leg({
      required String mode,
      required String from,
      required String to,
      required int startOffsetMinutes,
      required int durationMinutes,
      required double distance,
    }) {
      final start = base + Duration(minutes: startOffsetMinutes).inMilliseconds;
      final end = start + Duration(minutes: durationMinutes).inMilliseconds;
      return RouteLeg(
        mode: mode,
        routeId: mode == 'WALK' ? '' : 'PREVIEW:$mode',
        fromName: from,
        fromLat: 0,
        fromLon: 0,
        toName: to,
        toLat: 0,
        toLon: 0,
        startTime: start,
        endTime: end,
        distance: distance,
      );
    }

    final routes = List<RouteOption>.generate(12, (i) {
      final firstWalk = 4 + (i % 3);
      final busRide = 18 + (i * 2);
      final secondWalk = 3 + (i % 4);
      final transfers = i % 2;
      return RouteOption(
        durationSeconds:
            (firstWalk + busRide + secondWalk + transfers * 6) * 60,
        transfers: transfers,
        walkDistanceMeters: 350 + i * 50,
        estimatedPriceLei: 5,
        fareRule: '5 lei / 90 min from first transit boarding',
        legs: [
          leg(
            mode: 'WALK',
            from: request.origin,
            to: 'Nearest stop',
            startOffsetMinutes: 0,
            durationMinutes: firstWalk,
            distance: 220 + i * 10,
          ),
          leg(
            mode: 'BUS',
            from: 'Nearest stop',
            to: transfers == 0 ? request.destination : 'Central interchange',
            startOffsetMinutes: firstWalk + 2,
            durationMinutes: busRide,
            distance: 4300 + i * 150,
          ),
          if (transfers == 1)
            leg(
              mode: 'TRAM',
              from: 'Central interchange',
              to: request.destination,
              startOffsetMinutes: firstWalk + busRide + 8,
              durationMinutes: 9,
              distance: 1800 + i * 60,
            ),
          leg(
            mode: 'WALK',
            from: 'Final stop',
            to: request.destination,
            startOffsetMinutes: firstWalk + busRide + 10,
            durationMinutes: secondWalk,
            distance: 130 + i * 8,
          ),
        ],
      );
    });
    return RouteSearchResponse(
      cityId: request.cityId,
      cityName: 'Preview City',
      offset: request.offset,
      limit: request.limit,
      total: routes.length,
      routes: routes,
    );
  }
}
