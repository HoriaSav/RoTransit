import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/format/search_text_normalizer.dart';
import '../../../local/local_db.dart';
import '../domain/route_models.dart';
import 'stop_suggestion_dedupe.dart';
import '../../map/data/companion_catalog.dart';

final offlineTransitCacheRepositoryProvider =
    Provider<OfflineTransitCacheRepository>(
  (ref) => OfflineTransitCacheRepository(),
);

class OfflineTransitMeta {
  const OfflineTransitMeta({
    required this.cityId,
    required this.anchorMondayIso,
    required this.downloadedAtIso,
    required this.packVersion,
    required this.schemaVersion,
  });

  final String cityId;
  final String anchorMondayIso;
  final String downloadedAtIso;
  /// Server fingerprint; empty for packs saved before this field existed.
  final String packVersion;
  final int schemaVersion;
}

/// Prefer [OfflineTransitMeta.packVersion] when the backend sends it; otherwise a
/// stable short fingerprint so Settings is never blank for an installed pack.
String offlinePackLocalDisplayVersion(OfflineTransitMeta meta) {
  final v = meta.packVersion.trim();
  if (v.isNotEmpty) return v;
  final h = Object.hash(
    meta.cityId,
    meta.anchorMondayIso,
    meta.downloadedAtIso,
  );
  final hex = (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  final week = meta.anchorMondayIso.trim();
  if (week.isEmpty) return 'local#$hex';
  return 'local#$hex · week $week';
}

/// Persists the bulk offline-pack payload for one city.
class OfflineTransitCacheRepository {
  static const _schemaVersion = 1;

  /// In-memory unique stops per city (invalidated when a pack is applied).
  final Map<String, List<StopSearchItem>> _uniqueStopsByCity = {};

  void _invalidateUniqueStopsForCity(String cityId) {
    if (cityId.isEmpty) return;
    _uniqueStopsByCity.remove(cityId);
  }

  String _mergeKeyForStop(RouteStop s) {
    final id = s.stopId.trim();
    if (id.isNotEmpty) return id;
    return '${s.lat},${s.lon}';
  }

  /// All distinct stops from the offline pack for [cityId], for picker / local search.
  Future<List<StopSearchItem>> uniqueStopsForCity(String cityId) async {
    if (cityId.isEmpty) return const [];
    final cached = _uniqueStopsByCity[cityId];
    if (cached != null) return cached;

    // Bundled Brașov companion pack is authoritative for map/search.
    try {
      final companion = CompanionCatalog.instance;
      final meta = await companion.meta();
      if (cityId == meta.cityId || cityId.isEmpty) {
        final stops = await companion.allStops();
        if (stops.isNotEmpty) {
          _uniqueStopsByCity[cityId] = stops;
          return stops;
        }
      }
    } catch (_) {}

    final meta = await getMetaForCity(cityId);
    if (meta == null) {
      _uniqueStopsByCity[cityId] = const [];
      return const [];
    }

    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_route_stops',
      columns: ['stops_json'],
      where: 'city_id = ?',
      whereArgs: [cityId],
    );

    final byKey = <String, StopSearchItem>{};
    for (final row in rows) {
      final raw = row['stops_json'] as String?;
      if (raw == null || raw.isEmpty) continue;
      List<dynamic> list;
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }
      for (final e in list.whereType<Map<String, dynamic>>()) {
        final stop = RouteStop.fromJson(e);
        if (stop.name.trim().isEmpty) continue;
        final key = _mergeKeyForStop(stop);
        byKey.putIfAbsent(
          key,
          () => StopSearchItem(
            stopId: stop.stopId,
            name: stop.name,
            lat: stop.lat,
            lon: stop.lon,
          ),
        );
      }
    }

    final out = byKey.values.toList();
    _uniqueStopsByCity[cityId] = out;
    return out;
  }

  /// Proximity-ranked stops from the offline pack (same radius semantics as API nearby).
  Future<List<StopSearchItem>> nearbyStopsFromPack({
    required String cityId,
    required double lat,
    required double lon,
    int radiusMeters = 5000,
    int limit = 40,
  }) async {
    final all = await uniqueStopsForCity(cityId);
    if (all.isEmpty) return const [];

    final inRadius = <StopSearchItem>[];
    for (final s in all) {
      final d = stopSuggestionDistanceMeters(lat, lon, s.lat, s.lon);
      if (d <= radiusMeters) inRadius.add(s);
    }
    inRadius.sort(
      (a, b) => stopSuggestionDistanceMeters(lat, lon, a.lat, a.lon)
          .compareTo(stopSuggestionDistanceMeters(lat, lon, b.lat, b.lon)),
    );

    final nearby = inRadius
        .map(
          (e) => NearbyStopItem(
            stopId: e.stopId,
            name: e.name,
            lat: e.lat,
            lon: e.lon,
          ),
        )
        .toList();

    final deduped = dedupeNearbyStopItems(
      nearby,
      limit,
      refLat: lat,
      refLon: lon,
    );
    return deduped
        .map(
          (e) => StopSearchItem(
            stopId: e.stopId,
            name: e.name,
            lat: e.lat,
            lon: e.lon,
          ),
        )
        .toList();
  }

  /// Local substring search over pack stops (offline typeahead).
  Future<List<StopSearchItem>> searchStopsInPack({
    required String cityId,
    required String query,
    int limit = 20,
    double? refLat,
    double? refLon,
  }) async {
    final q = normalizeSearchText(query);
    if (q.isEmpty) return const [];

    final all = await uniqueStopsForCity(cityId);
    if (all.isEmpty) return const [];

    final filtered = all
        .where((s) => normalizeSearchText(s.name).contains(q))
        .toList();
    if (filtered.isEmpty) return const [];

    final rLat = refLat;
    final rLon = refLon;
    if (rLat != null && rLon != null) {
      filtered.sort(
        (a, b) => stopSuggestionDistanceMeters(rLat, rLon, a.lat, a.lon)
            .compareTo(stopSuggestionDistanceMeters(rLat, rLon, b.lat, b.lon)),
      );
    }

    return dedupeStopSearchItems(
      filtered,
      limit,
      refLat: refLat,
      refLon: refLon,
    );
  }

  Future<String?> getLatestCachedCityId() async {
    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_transit_meta',
      columns: ['city_id'],
      orderBy: 'downloaded_at_iso DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final cityId = rows.first['city_id'] as String?;
    if (cityId == null || cityId.isEmpty) return null;
    return cityId;
  }

  Future<OfflineTransitMeta?> getMetaForCity(String cityId) async {
    if (cityId.isEmpty) return null;
    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_transit_meta',
      where: 'city_id = ?',
      whereArgs: [cityId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OfflineTransitMeta(
      cityId: row['city_id'] as String,
      anchorMondayIso: row['anchor_monday_iso'] as String,
      downloadedAtIso: row['downloaded_at_iso'] as String,
      packVersion: (row['pack_version'] as String?) ?? '',
      schemaVersion: (row['schema_version'] as int?) ?? 1,
    );
  }

  /// Parses and stores [json] from `GET /api/buses/offline-pack`.
  Future<void> applyOfflinePackJson(
    Map<String, dynamic> json, {
    String? expectedCityId,
  }) async {
    final cityId = (json['cityId'] ?? '').toString();
    if (cityId.isEmpty) {
      throw StateError('offline-pack missing cityId');
    }
    if (expectedCityId != null &&
        expectedCityId.isNotEmpty &&
        expectedCityId != cityId) {
      throw StateError(
        'offline-pack cityId mismatch: expected $expectedCityId got $cityId',
      );
    }
    final anchorMonday = (json['anchorMonday'] ?? '').toString();
    if (anchorMonday.isEmpty) {
      throw StateError('offline-pack missing anchorMonday');
    }
    final generatedAt = (json['generatedAt'] ?? '').toString();
    final downloadedAt =
        generatedAt.isNotEmpty ? generatedAt : DateTime.now().toIso8601String();
    final packVersion = (json['packVersion'] ?? '').toString();

    final busesRaw = json['buses'] as List<dynamic>? ?? <dynamic>[];
    final buses = busesRaw
        .whereType<Map<String, dynamic>>()
        .map(BusLine.fromJson)
        .toList();

    final routeStopsRaw =
        json['routeStops'] as List<dynamic>? ?? <dynamic>[];
    final timetablesRaw =
        json['timetables'] as List<dynamic>? ?? <dynamic>[];

    final db = await LocalDb.instance();
    await db.transaction((txn) async {
      await _deleteCity(txn, cityId);

      await txn.insert('offline_transit_meta', {
        'city_id': cityId,
        'anchor_monday_iso': anchorMonday,
        'downloaded_at_iso': downloadedAt,
        'pack_version': packVersion,
        'schema_version': _schemaVersion,
      });

      await txn.insert('offline_bus_lines', {
        'city_id': cityId,
        'buses_json': jsonEncode(buses.map((b) => _busLineToJson(b)).toList()),
      });

      for (final entry in routeStopsRaw.whereType<Map<String, dynamic>>()) {
        final routeId = (entry['routeId'] ?? '').toString();
        final directionId = (entry['directionId'] ?? '').toString();
        final stops = (entry['stops'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RouteStop.fromJson)
            .toList();
        await txn.insert(
          'offline_route_stops',
          {
            'city_id': cityId,
            'route_id': routeId,
            'direction_id': directionId,
            'stops_json': jsonEncode(
              stops.map((s) => _routeStopToJson(s)).toList(),
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final entry in timetablesRaw.whereType<Map<String, dynamic>>()) {
        final routeId = (entry['routeId'] ?? '').toString();
        final stopId = (entry['stopId'] ?? '').toString();
        final directionId = (entry['directionId'] ?? '').toString();
        final dayKind = (entry['dayKind'] ?? '').toString();
        final timetableMap = entry['timetable'];
        if (timetableMap is! Map<String, dynamic>) continue;
        await txn.insert(
          'offline_timetables',
          {
            'city_id': cityId,
            'route_id': routeId,
            'stop_id': stopId,
            'direction_id': directionId,
            'day_kind': dayKind,
            'timetable_json': jsonEncode(timetableMap),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _invalidateUniqueStopsForCity(cityId);
  }

  Future<List<BusLine>?> getBuses(String cityId) async {
    if (cityId.isEmpty) return null;
    try {
      final companion = CompanionCatalog.instance;
      final meta = await companion.meta();
      if (cityId == meta.cityId) {
        return companion.listBuses();
      }
    } catch (_) {}
    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_bus_lines',
      columns: ['buses_json'],
      where: 'city_id = ?',
      whereArgs: [cityId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['buses_json'] as String?;
    if (raw == null || raw.isEmpty) return <BusLine>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(BusLine.fromJson)
        .toList();
  }

  Future<List<RouteStop>?> getRouteStops({
    required String cityId,
    required String routeId,
    String? directionId,
  }) async {
    if (cityId.isEmpty) return null;
    try {
      final companion = CompanionCatalog.instance;
      final meta = await companion.meta();
      if (cityId == meta.cityId) {
        final stops = await companion.routeStops(
          routeId: routeId,
          directionId: directionId ?? '0',
        );
        if (stops.isNotEmpty) return stops;
      }
    } catch (_) {}
    final dir = directionId ?? '';
    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_route_stops',
      columns: ['stops_json'],
      where: 'city_id = ? AND route_id = ? AND direction_id = ?',
      whereArgs: [cityId, routeId, dir],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['stops_json'] as String?;
    if (raw == null || raw.isEmpty) return <RouteStop>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(RouteStop.fromJson)
        .toList();
  }

  /// Uses [serviceDate] weekday to pick MONFRI / SATURDAY / SUNDAY slice (same as Bus tab).
  Future<StopTimetable?> getTimetable({
    required String cityId,
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? directionId,
  }) async {
    if (cityId.isEmpty) return null;
    try {
      final companion = CompanionCatalog.instance;
      final meta = await companion.meta();
      if (cityId == meta.cityId) {
        return companion.timetable(
          routeId: routeId,
          stopId: stopId,
          serviceDate: serviceDate,
          directionId: directionId ?? '0',
        );
      }
    } catch (_) {}
    final dir = directionId ?? '';
    final dayKind = dayKindForServiceDate(serviceDate);
    final db = await LocalDb.instance();
    final rows = await db.query(
      'offline_timetables',
      columns: ['timetable_json'],
      where:
          'city_id = ? AND route_id = ? AND stop_id = ? AND direction_id = ? AND day_kind = ?',
      whereArgs: [cityId, routeId, stopId, dir, dayKind],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['timetable_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final tt = StopTimetable.fromJson(map);
    final iso =
        '${serviceDate.year.toString().padLeft(4, '0')}-${serviceDate.month.toString().padLeft(2, '0')}-${serviceDate.day.toString().padLeft(2, '0')}';
    return StopTimetable(
      cityId: tt.cityId.isEmpty ? cityId : tt.cityId,
      routeId: tt.routeId.isEmpty ? routeId : tt.routeId,
      stopId: tt.stopId.isEmpty ? stopId : tt.stopId,
      serviceDate: iso,
      departures: tt.departures,
    );
  }

  static String dayKindForServiceDate(DateTime serviceDate) {
    final wd = serviceDate.weekday;
    if (wd == DateTime.saturday) return 'SATURDAY';
    if (wd == DateTime.sunday) return 'SUNDAY';
    return 'MONFRI';
  }

  Future<void> _deleteCity(Transaction txn, String cityId) async {
    await txn.delete(
      'offline_transit_meta',
      where: 'city_id = ?',
      whereArgs: [cityId],
    );
    await txn.delete(
      'offline_bus_lines',
      where: 'city_id = ?',
      whereArgs: [cityId],
    );
    await txn.delete(
      'offline_route_stops',
      where: 'city_id = ?',
      whereArgs: [cityId],
    );
    await txn.delete(
      'offline_timetables',
      where: 'city_id = ?',
      whereArgs: [cityId],
    );
  }

  Map<String, dynamic> _busLineToJson(BusLine b) => {
        'routeId': b.routeId,
        'shortName': b.shortName,
        'longName': b.longName,
        'mode': b.mode,
      };

  Map<String, dynamic> _routeStopToJson(RouteStop s) => {
        'stopId': s.stopId,
        'name': s.name,
        'lat': s.lat,
        'lon': s.lon,
        'stopSequence': s.stopSequence,
      };
}
