import 'dart:convert';

class RouteSearchRequest {
  const RouteSearchRequest({
    required this.cityId,
    required this.origin,
    required this.destination,
    required this.serviceDate,
    required this.serviceTime,
    this.passengerCount = 1,
    this.offset = 0,
    this.limit = 10,
  });

  final String cityId;
  final String origin;
  final String destination;
  final DateTime serviceDate;
  final DateTime serviceTime;
  final int passengerCount;
  final int offset;
  final int limit;
}

class CityItem {
  const CityItem({
    required this.id,
    required this.name,
    required this.country,
  });

  final String id;
  final String name;
  final String country;

  factory CityItem.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['cityId'] ?? '').toString();
    final country = (json['country'] ?? json['countryCode'] ?? '').toString();
    return CityItem(
      id: id,
      name: (json['name'] ?? '').toString(),
      country: country,
    );
  }
}

class NearbyStopItem {
  const NearbyStopItem({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String stopId;
  final String name;
  final double lat;
  final double lon;

  factory NearbyStopItem.fromJson(Map<String, dynamic> json) {
    return NearbyStopItem(
      stopId: json['stopId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StopSearchItem {
  const StopSearchItem({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String stopId;
  final String name;
  final double lat;
  final double lon;

  factory StopSearchItem.fromJson(Map<String, dynamic> json) {
    return StopSearchItem(
      stopId: json['stopId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RouteOption {
  const RouteOption({
    required this.durationSeconds,
    required this.transfers,
    required this.walkDistanceMeters,
    this.estimatedPriceLei = 0,
    this.fareRule = '',
    required this.legs,
  });

  final int durationSeconds;
  final int transfers;
  final int walkDistanceMeters;
  final int estimatedPriceLei;
  final String fareRule;
  final List<RouteLeg> legs;

  Map<String, dynamic> toJson() => {
        'durationSeconds': durationSeconds,
        'transfers': transfers,
        'walkDistanceMeters': walkDistanceMeters,
        'estimatedPriceLei': estimatedPriceLei,
        'fareRule': fareRule,
        'legs': legs.map((e) => e.toJson()).toList(),
      };

  static RouteOption fromJson(Map<String, dynamic> json) {
    return RouteOption(
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      transfers: (json['transfers'] as num).toInt(),
      walkDistanceMeters: (json['walkDistanceMeters'] as num).toInt(),
      estimatedPriceLei: (json['estimatedPriceLei'] as num?)?.toInt() ?? 0,
      fareRule: json['fareRule'] as String? ?? '',
      legs: (json['legs'] as List<dynamic>)
          .map((e) => RouteLeg.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RouteLeg {
  const RouteLeg({
    required this.mode,
    required this.routeId,
    required this.fromName,
    required this.fromLat,
    required this.fromLon,
    required this.toName,
    required this.toLat,
    required this.toLon,
    required this.startTime,
    required this.endTime,
    required this.distance,
    this.geometry = const [],
    this.stops = const [],
  });

  final String mode;
  final String routeId;
  final String fromName;
  final double fromLat;
  final double fromLon;
  final String toName;
  final double toLat;
  final double toLon;
  final int startTime;
  final int endTime;
  final double distance;
  final List<RouteLegPoint> geometry;
  final List<RouteLegStop> stops;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'routeId': routeId,
        'fromName': fromName,
        'fromLat': fromLat,
        'fromLon': fromLon,
        'toName': toName,
        'toLat': toLat,
        'toLon': toLon,
        'startTime': startTime,
        'endTime': endTime,
        'distance': distance,
        'geometry': geometry.map((e) => e.toJson()).toList(),
        'stops': stops.map((e) => e.toJson()).toList(),
      };

  static RouteLeg fromJson(Map<String, dynamic> json) {
    final geometry = (json['geometry'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RouteLegPoint.fromJson)
        .toList();
    final stops = (json['stops'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RouteLegStop.fromJson)
        .toList();
    return RouteLeg(
      mode: json['mode'] as String? ?? '',
      routeId: json['routeId'] as String? ?? '',
      fromName: json['fromName'] as String? ?? '',
      fromLat: (json['fromLat'] as num?)?.toDouble() ?? 0,
      fromLon: (json['fromLon'] as num?)?.toDouble() ?? 0,
      toName: json['toName'] as String? ?? '',
      toLat: (json['toLat'] as num?)?.toDouble() ?? 0,
      toLon: (json['toLon'] as num?)?.toDouble() ?? 0,
      startTime: (json['startTime'] as num?)?.toInt() ?? 0,
      endTime: (json['endTime'] as num?)?.toInt() ?? 0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      geometry: geometry,
      stops: stops,
    );
  }
}

class RouteLegPoint {
  const RouteLegPoint({
    required this.lat,
    required this.lon,
  });

  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
      };

  factory RouteLegPoint.fromJson(Map<String, dynamic> json) {
    return RouteLegPoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RouteLegStop {
  const RouteLegStop({
    required this.name,
    required this.lat,
    required this.lon,
    required this.stopSequence,
  });

  final String name;
  final double lat;
  final double lon;
  final int stopSequence;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        'stopSequence': stopSequence,
      };

  factory RouteLegStop.fromJson(Map<String, dynamic> json) {
    return RouteLegStop(
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
      stopSequence: (json['stopSequence'] as num?)?.toInt() ?? 0,
    );
  }
}

class RouteSearchResponse {
  const RouteSearchResponse({
    required this.cityId,
    required this.cityName,
    this.offset = 0,
    this.limit = 10,
    this.total = 0,
    required this.routes,
  });

  final String cityId;
  final String cityName;
  final int offset;
  final int limit;
  final int total;
  final List<RouteOption> routes;
}

class BusLine {
  const BusLine({
    required this.routeId,
    required this.shortName,
    required this.longName,
    required this.mode,
  });

  final String routeId;
  final String shortName;
  final String longName;
  final String mode;

  factory BusLine.fromJson(Map<String, dynamic> json) {
    return BusLine(
      routeId: json['routeId'] as String? ?? '',
      shortName: json['shortName'] as String? ?? '',
      longName: json['longName'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
    );
  }
}

class RouteStop {
  const RouteStop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.stopSequence,
  });

  final String stopId;
  final String name;
  final double lat;
  final double lon;
  final int stopSequence;

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      stopId: json['stopId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
      stopSequence: (json['stopSequence'] as num?)?.toInt() ?? 0,
    );
  }
}

class StopTimetableEntry {
  const StopTimetableEntry({
    required this.tripId,
    required this.headsign,
    required this.departureTime,
  });

  final String tripId;
  final String headsign;
  final String departureTime;

  factory StopTimetableEntry.fromJson(Map<String, dynamic> json) {
    return StopTimetableEntry(
      tripId: json['tripId'] as String? ?? '',
      headsign: json['headsign'] as String? ?? '',
      departureTime: json['departureTime'] as String? ?? '',
    );
  }
}

class StopTimetable {
  const StopTimetable({
    required this.cityId,
    required this.routeId,
    required this.stopId,
    required this.serviceDate,
    required this.departures,
  });

  final String cityId;
  final String routeId;
  final String stopId;
  final String serviceDate;
  final List<StopTimetableEntry> departures;

  factory StopTimetable.fromJson(Map<String, dynamic> json) {
    final departures = (json['departures'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => StopTimetableEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return StopTimetable(
      cityId: json['cityId'] as String? ?? '',
      routeId: json['routeId'] as String? ?? '',
      stopId: json['stopId'] as String? ?? '',
      serviceDate: json['serviceDate'] as String? ?? '',
      departures: departures,
    );
  }
}

class SavedRouteValidation {
  const SavedRouteValidation({
    required this.isValid,
    required this.reason,
  });

  final bool isValid;
  final String reason;

  factory SavedRouteValidation.fromJson(Map<String, dynamic> json) {
    return SavedRouteValidation(
      isValid: json['isValid'] as bool? ?? false,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class SavedRouteItem {
  const SavedRouteItem({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.label,
    required this.routeMetadata,
    required this.createdAt,
  });

  final String id;
  final String cityId;
  final String cityName;
  final String label;
  final String routeMetadata;
  final DateTime createdAt;

  factory SavedRouteItem.fromJson(Map<String, dynamic> json) {
    return SavedRouteItem(
      id: json['id'] as String? ?? '',
      cityId: json['cityId'] as String? ?? '',
      cityName: json['cityName'] as String? ?? '',
      label: json['label'] as String? ?? 'Saved journey',
      routeMetadata: json['routeMetadata'] as String? ?? '{}',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String encodeRouteMetadata(RouteOption option) => jsonEncode(option.toJson());

RouteOption decodeRouteMetadata(String metadata) =>
    RouteOption.fromJson(jsonDecode(metadata) as Map<String, dynamic>);
