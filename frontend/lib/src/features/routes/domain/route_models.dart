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
