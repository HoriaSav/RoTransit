import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

/// Manifest written next to the pack by `scripts/data/build_brasov_companion_pack.py`.
const kBrasovCompanionManifest = 'assets/data/brasov_companion.manifest.json';

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
    this.firstStopName = '',
    this.lastStopName = '',
    this.minutesAfterStart = 0,
  });

  final String routeId;
  final String shortName;
  final String longName;
  final String directionId;
  final String headsign;
  final String departureTime;
  final String tripId;

  /// Where this trip starts and ends (both ends of the ride).
  final String firstStopName;
  final String lastStopName;

  /// Wall-clock minutes after the board's start time.
  final int minutesAfterStart;
}

/// Top-level so the isolate closure captures only the bytes.
List<int> _gunzip(Uint8List bytes) => gzip.decode(bytes);

final companionCatalogProvider = Provider<CompanionCatalog>((ref) {
  return CompanionCatalog.instance;
});

/// The pack's last service date when [now]'s day is after it (the
/// timetables ended and the app needs an update), else null.
Future<DateTime?> feedEndedOn(CompanionCatalog catalog, DateTime now) async {
  final range = await catalog.feedDateRange();
  final today = DateTime(now.year, now.month, now.day);
  return range != null && today.isAfter(range.end) ? range.end : null;
}

/// Read-only Brașov catalog shipped in the app binary (no RoTransit server).
class CompanionCatalog {
  CompanionCatalog._();
  static final CompanionCatalog instance = CompanionCatalog._();

  Database? _db;
  Future<Database>? _openFuture;
  CompanionPackMeta? _meta;
  List<StopSearchItem>? _allStops;
  Map<String, BusLine>? _routesById;
  Map<String, String>? _dayOverrides;
  ({DateTime start, DateTime end})? _feedRange;

  /// Drops the open handle and caches (tests use a fresh documents dir each).
  @visibleForTesting
  Future<void> reset() async {
    final db = _db;
    _db = null;
    _openFuture = null;
    _meta = null;
    _allStops = null;
    _routesById = null;
    _dayOverrides = null;
    _feedRange = null;
    await db?.close();
  }

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
    // Re-extract whenever the bundled pack changes (new app build with new data).
    final manifest = jsonDecode(
      await rootBundle.loadString(kBrasovCompanionManifest),
    ) as Map<String, dynamic>;
    final assetRev = (manifest['pack_version'] ?? '').toString().trim();
    if (assetRev.isEmpty) {
      // An empty marker never changes, so the pack would never be refreshed.
      throw StateError('$kBrasovCompanionManifest has no pack_version');
    }
    final marker = File(markerPath);
    final needsCopy = !File(dbPath).existsSync() ||
        !marker.existsSync() ||
        (await marker.readAsString()).trim() != assetRev;
    if (needsCopy) {
      final gz = await rootBundle.load(kBrasovCompanionAssetGz);
      final bytes = gz.buffer.asUint8List(gz.offsetInBytes, gz.lengthInBytes);
      // ~27 MB decode: keep it off the UI isolate.
      final raw = await Isolate.run(() => _gunzip(bytes));
      final dbFile = File(dbPath);
      if (dbFile.existsSync()) await dbFile.delete();
      await dbFile.writeAsBytes(raw, flush: true);
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

  /// YYYY-MM-DD (also how dates are shown next to the pack's data date).
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Which weekday schedule [date] runs: public holidays from GTFS
  /// `calendar_dates` (pack table `day_overrides`) win over the weekday.
  /// Not used by [timetable] (weekly tab shows the regular pattern) nor by
  /// [stopBoard] (filters by service directly).
  Future<String> serviceDayKindFor(DateTime date) async {
    var overrides = _dayOverrides;
    if (overrides == null) {
      final db = await _ensureDb();
      overrides = <String, String>{};
      try {
        final rows = await db.query('day_overrides');
        for (final r in rows) {
          overrides[r['service_date'] as String] = r['day_kind'] as String;
        }
      } on DatabaseException {
        // Older pack without the table: weekday only.
      }
      _dayOverrides = overrides;
    }
    return overrides[isoDate(date)] ?? dayKindFor(date);
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

  /// HH:MM[:SS] → seconds since midnight (allows >24h).
  static int? timeToSeconds(String raw) {
    final mins = timeToMinutes(raw);
    if (mins == null) return null;
    final parts = raw.trim().split(':');
    final s = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    return mins * 60 + s;
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
    // The weekly tab shows the regular Mon–Fri / Sat / Sun pattern; a
    // holiday in this week does not change it (the dated stop board does).
    final dayKind = dayKindFor(serviceDate);
    final rows = await db.query(
      'departures',
      columns: ['trip_id', 'headsign', 'departure_time'],
      where:
          'route_id = ? AND stop_id = ? AND direction_id = ? AND day_kind = ?',
      whereArgs: [routeId, stopId, dir, dayKind],
      orderBy: 'departure_time ASC',
    );
    final iso = isoDate(serviceDate);
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

  /// First and last date any service in the pack runs (GTFS calendar range
  /// plus added dates). After the end the board has nothing to show.
  Future<({DateTime start, DateTime end})?> feedDateRange() async {
    final cached = _feedRange;
    if (cached != null) return cached;
    final db = await _ensureDb();
    final rows = await db.rawQuery('''
      SELECT MIN(d) AS first, MAX(d) AS last FROM (
        SELECT start_date AS d FROM services
        UNION ALL SELECT end_date FROM services
        UNION ALL SELECT service_date FROM service_exceptions
          WHERE exception_type = 1
      )
    ''');
    final first = DateTime.tryParse(rows.first['first'] as String? ?? '');
    final last = DateTime.tryParse(rows.first['last'] as String? ?? '');
    if (first == null || last == null) return null;
    return _feedRange = (start: first, end: last);
  }

  /// Service days a stop board starting at [from] needs, with each day's
  /// minute offset from [from]'s midnight: the previous day (GTFS times
  /// >= 24:00), today and, when the window crosses midnight, the next day.
  ///
  /// Uses calendar dates, not `Duration(days: 1)`, which lands on the wrong
  /// day around DST changes.
  static List<(DateTime, int)> stopBoardServiceDays(
    DateTime from,
    int windowMinutes,
  ) {
    final endMin = from.hour * 60 + from.minute + windowMinutes;
    return [
      (DateTime(from.year, from.month, from.day - 1), -24 * 60),
      (DateTime(from.year, from.month, from.day), 0),
      if (endMin > 24 * 60)
        (DateTime(from.year, from.month, from.day + 1), 24 * 60),
    ];
  }

  static const _weekdayColumns = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Scheduled departures at [stopId] from [from] for [windowMinutes].
  ///
  /// Only trips whose GTFS service runs on that date are included (calendar
  /// weekdays and date range, plus `calendar_dates` additions/removals), so
  /// holidays and school-only trips follow the feed.
  Future<List<StopBoardDeparture>> stopBoard({
    required String stopId,
    required DateTime from,
    required int windowMinutes,
  }) async {
    final db = await _ensureDb();
    final routes = await routesById();
    final startMin = from.hour * 60 + from.minute;
    final endMin = startMin + windowMinutes;
    // (effective seconds from [from]'s midnight, row)
    final found = <(int, StopBoardDeparture)>[];
    for (final (day, offset) in stopBoardServiceDays(from, windowMinutes)) {
      final iso = isoDate(day);
      final weekdayColumn = _weekdayColumns[day.weekday - 1];
      final rows = await db.rawQuery(
        '''
        WITH active(service_id) AS (
          SELECT service_id FROM services
            WHERE $weekdayColumn = 1 AND ? BETWEEN start_date AND end_date
          UNION
          SELECT service_id FROM service_exceptions
            WHERE service_date = ? AND exception_type = 1
          EXCEPT
          SELECT service_id FROM service_exceptions
            WHERE service_date = ? AND exception_type = 2
        )
        SELECT DISTINCT d.route_id, d.direction_id, d.trip_id, d.headsign,
          d.departure_time, t.first_stop_name, t.last_stop_name
        FROM departures d
        LEFT JOIN trips t ON t.trip_id = d.trip_id
        WHERE d.stop_id = ? AND d.service_id IN (SELECT service_id FROM active)
        ''',
        [iso, iso, iso, stopId],
      );
      for (final r in rows) {
        final dep = r['departure_time'] as String? ?? '';
        final secs = timeToSeconds(dep);
        if (secs == null) continue;
        final at = secs ~/ 60 + offset;
        if (at < startMin || at >= endMin) continue;
        final routeId = r['route_id'] as String;
        final line = routes[routeId];
        found.add((
          secs + offset * 60,
          StopBoardDeparture(
            routeId: routeId,
            shortName: line?.shortName ?? routeId,
            longName: line?.longName ?? '',
            directionId: r['direction_id'] as String? ?? '0',
            headsign: r['headsign'] as String? ?? '',
            departureTime: dep,
            tripId: r['trip_id'] as String? ?? '',
            firstStopName: r['first_stop_name'] as String? ?? '',
            lastStopName: r['last_stop_name'] as String? ?? '',
            minutesAfterStart: at - startMin,
          ),
        ));
      }
    }
    // Total order (time to the second, then GTFS trip_id) so rows never swap
    // places when the window grows.
    found.sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$2.tripId.compareTo(b.$2.tripId);
    });
    return [for (final f in found) f.$2];
  }
}
