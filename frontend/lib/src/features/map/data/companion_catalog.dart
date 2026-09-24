import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/format/search_text_normalizer.dart';
import '../../routes/domain/route_models.dart';
import '../../routes/data/stop_suggestion_dedupe.dart';

/// Asset path for the gzipped Brașov companion SQLite pack.
const kBrasovCompanionAssetGz = 'assets/data/brasov_companion.sqlite.gz';

class CompanionPackMeta {
  const CompanionPackMeta({
    required this.cityId,
    required this.cityName,
    required this.anchorMonday,
    required this.dataAsOf,
    required this.generatedAt,
    required this.packVersion,
    required this.source,
  });

  final String cityId;
  final String cityName;
  final String anchorMonday;
  final String dataAsOf;
  final String generatedAt;
  final String packVersion;
  final String source;
}

class StopBoardDeparture {
  const StopBoardDeparture({
    required this.routeId,
    required this.shortName,
    required this.longName,
    required this.directionId,
    required this.headsign,
    required this.departureTime,
    required this.tripId,
  });

  final String routeId;
  final String shortName;
  final String longName;
  final String directionId;
  final String headsign;
  final String departureTime;
  final String tripId;
}

final companionCatalogProvider = Provider<CompanionCatalog>((ref) {
  return CompanionCatalog.instance;
});

/// Read-only Brașov catalog shipped in the app binary (no RoTransit server).
class CompanionCatalog {
  CompanionCatalog._();
  static final CompanionCatalog instance = CompanionCatalog._();

  Database? _db;
  Future<Database>? _openFuture;
  CompanionPackMeta? _meta;
  List<StopSearchItem>? _allStops;
  Map<String, BusLine>? _routesById;

  Future<Database> _ensureDb() {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    // If a prior open failed, clear so callers can retry (bootstrap catch must
    // not permanently poison Timetable / Bus providers).
    return _openFuture ??= _openDb().catchError((Object e, StackTrace st) {
      _openFuture = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<Database> _openDb() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'companion'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dbPath = p.join(dir.path, 'brasov_companion.sqlite');
    final markerPath = p.join(dir.path, 'brasov_companion.asset_rev');
    const assetRev = '1';
    final marker = File(markerPath);
    final needsCopy = !File(dbPath).existsSync() ||
        !marker.existsSync() ||
        (await marker.readAsString()).trim() != assetRev;
    if (needsCopy) {
      final gz = await rootBundle.load(kBrasovCompanionAssetGz);
      final raw = gzip.decode(gz.buffer.asUint8List());
      await File(dbPath).writeAsBytes(raw, flush: true);
      await marker.writeAsString(assetRev);
    }
    final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    _db = db;
    return db;
  }

  Future<CompanionPackMeta> meta() async {
    final cached = _meta;
    if (cached != null) return cached;
    final db = await _ensureDb();
    final rows = await db.query('meta');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    final m = CompanionPackMeta(
      cityId: map['city_id'] ?? kBrasovCityId,
      cityName: map['city_name'] ?? kBrasovCityName,
      anchorMonday: map['anchor_monday'] ?? '',
      dataAsOf: map['data_as_of'] ?? '',
      generatedAt: map['generated_at'] ?? '',
      packVersion: map['pack_version'] ?? '',
      source: map['source'] ?? '',
    );
    _meta = m;
    return m;
  }

  Future<List<StopSearchItem>> allStops() async {
    final cached = _allStops;
    if (cached != null) return cached;
    final db = await _ensureDb();
    final rows = await db.query('stops', orderBy: 'name COLLATE NOCASE');
    final list = rows
        .map(
          (r) => StopSearchItem(
            stopId: r['stop_id'] as String,
            name: r['name'] as String,
            lat: (r['lat'] as num).toDouble(),
            lon: (r['lon'] as num).toDouble(),
          ),
        )
        .toList();
    _allStops = list;
    return list;
  }

  Future<List<StopSearchItem>> searchStops(String query, {int limit = 20}) async {
    final q = normalizeSearchText(query);
    if (q.isEmpty) return const [];
    final all = await allStops();
    final filtered =
        all.where((s) => normalizeSearchText(s.name).contains(q)).toList();
    return dedupeStopSearchItems(filtered, limit);
  }

  Future<Map<String, BusLine>> routesById() async {
    final cached = _routesById;
    if (cached != null) return cached;
    final db = await _ensureDb();
    final rows = await db.query('routes');
    final map = <String, BusLine>{};
    for (final r in rows) {
      final id = r['route_id'] as String;
      map[id] = BusLine(
        routeId: id,
        shortName: r['short_name'] as String? ?? id,
        longName: r['long_name'] as String? ?? '',
        mode: r['mode'] as String? ?? 'BUS',
      );
    }
    _routesById = map;
    return map;
  }

  Future<List<BusLine>> listBuses() async {
    final map = await routesById();
    final list = map.values.toList();
    list.sort((a, b) => a.shortName.compareTo(b.shortName));
    return list;
  }

  Future<List<RouteStop>> routeStops({
    required String routeId,
    String? directionId,
  }) async {
    final db = await _ensureDb();
    final dir = directionId ?? '0';
    final rows = await db.query(
      'route_stops',
      where: 'route_id = ? AND direction_id = ?',
      whereArgs: [routeId, dir],
      orderBy: 'stop_sequence ASC',
    );
    return rows
        .map(
          (r) => RouteStop(
            stopId: r['stop_id'] as String,
            name: r['name'] as String,
            lat: (r['lat'] as num).toDouble(),
            lon: (r['lon'] as num).toDouble(),
            stopSequence: (r['stop_sequence'] as num).toInt(),
          ),
        )
        .toList();
  }

  static String dayKindFor(DateTime serviceDate) {
    final wd = serviceDate.weekday;
    if (wd == DateTime.saturday) return 'SATURDAY';
    if (wd == DateTime.sunday) return 'SUNDAY';
    return 'MONFRI';
  }

  /// HH:MM or HH:MM:SS → minutes since midnight (allows >24h).
  static int? timeToMinutes(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String minutesToHhMm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<StopTimetable> timetable({
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? directionId,
  }) async {
    final db = await _ensureDb();
    final dir = directionId ?? '0';
    final dayKind = dayKindFor(serviceDate);
    final rows = await db.query(
      'departures',
      columns: ['trip_id', 'headsign', 'departure_time'],
      where:
          'route_id = ? AND stop_id = ? AND direction_id = ? AND day_kind = ?',
      whereArgs: [routeId, stopId, dir, dayKind],
      orderBy: 'departure_time ASC',
    );
    final iso =
        '${serviceDate.year.toString().padLeft(4, '0')}-${serviceDate.month.toString().padLeft(2, '0')}-${serviceDate.day.toString().padLeft(2, '0')}';
    return StopTimetable(
      cityId: kBrasovCityId,
      routeId: routeId,
      stopId: stopId,
      serviceDate: iso,
      departures: rows
          .map(
            (r) => StopTimetableEntry(
              tripId: r['trip_id'] as String? ?? '',
              headsign: r['headsign'] as String? ?? '',
              departureTime: r['departure_time'] as String? ?? '',
            ),
          )
          .toList(),
    );
  }

  /// Scheduled departures at [stopId] from [from] for [windowMinutes].
  Future<List<StopBoardDeparture>> stopBoard({
    required String stopId,
    required DateTime from,
    required int windowMinutes,
  }) async {
    final db = await _ensureDb();
    final routes = await routesById();
    final dayKind = dayKindFor(from);
    final startMin = from.hour * 60 + from.minute;
    final endMin = startMin + windowMinutes;
    final rows = await db.query(
      'departures',
      where: 'stop_id = ? AND day_kind = ?',
      whereArgs: [stopId, dayKind],
      orderBy: 'departure_time ASC',
    );
    final out = <StopBoardDeparture>[];
    for (final r in rows) {
      final dep = r['departure_time'] as String? ?? '';
      final mins = timeToMinutes(dep);
      if (mins == null) continue;
      // Same calendar day window; also allow next-day wrap within 24h+slack.
      final candidates = <int>[mins, mins + 24 * 60];
      var matched = false;
      for (final c in candidates) {
        if (c >= startMin && c < endMin) {
          matched = true;
          break;
        }
      }
      if (!matched) continue;
      final routeId = r['route_id'] as String;
      final line = routes[routeId];
      out.add(
        StopBoardDeparture(
          routeId: routeId,
          shortName: line?.shortName ?? routeId,
          longName: line?.longName ?? '',
          directionId: r['direction_id'] as String? ?? '0',
          headsign: r['headsign'] as String? ?? '',
          departureTime: dep,
          tripId: r['trip_id'] as String? ?? '',
        ),
      );
    }
    out.sort((a, b) {
      final am = timeToMinutes(a.departureTime) ?? 0;
      final bm = timeToMinutes(b.departureTime) ?? 0;
      final aAdj = am < startMin ? am + 24 * 60 : am;
      final bAdj = bm < startMin ? bm + 24 * 60 : bm;
      return aAdj.compareTo(bAdj);
    });
    return out;
  }

  /// Ensures LocalDb offline meta/lines exist so Bus tab treats the pack as installed.
  Future<void> mirrorMetaIntoLocalOfflineCache(
    Future<void> Function(Map<String, dynamic> packJson) applyPack,
  ) async {
    final m = await meta();
    final buses = await listBuses();
    final db = await _ensureDb();
    final routeStopRows = await db.query('route_stops');
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final r in routeStopRows) {
      final key = '${r['route_id']}|${r['direction_id']}';
      byKey.putIfAbsent(key, () => []).add({
        'stopId': r['stop_id'],
        'name': r['name'],
        'lat': r['lat'],
        'lon': r['lon'],
        'stopSequence': r['stop_sequence'],
      });
    }
    final routeStops = <Map<String, dynamic>>[];
    for (final entry in byKey.entries) {
      final parts = entry.key.split('|');
      entry.value.sort(
        (a, b) =>
            ((a['stopSequence'] as num?) ?? 0).compareTo((b['stopSequence'] as num?) ?? 0),
      );
      routeStops.add({
        'routeId': parts[0],
        'directionId': parts[1],
        'stops': entry.value,
      });
    }

    // Timetables: leave empty here — Bus tab queries companion via repository bridge.
    final pack = {
      'cityId': m.cityId,
      'anchorMonday': m.anchorMonday.isEmpty ? '2026-01-19' : m.anchorMonday,
      'generatedAt': m.generatedAt.isEmpty
          ? DateTime.now().toUtc().toIso8601String()
          : m.generatedAt,
      'packVersion': m.packVersion,
      'buses': buses
          .map(
            (b) => {
              'routeId': b.routeId,
              'shortName': b.shortName,
              'longName': b.longName,
              'mode': b.mode,
            },
          )
          .toList(),
      'routeStops': routeStops,
      'timetables': <Map<String, dynamic>>[],
    };
    await applyPack(pack);
  }
}
