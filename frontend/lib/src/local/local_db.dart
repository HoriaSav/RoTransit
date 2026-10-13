import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Legacy on-device DB (`rotransit.db`). The app no longer reads it: Brașov
/// timetables come from the bundled pack and favorites live in
/// SharedPreferences. The tables are kept on purpose: `saved_routes` holds
/// old journeys from earlier versions (dropping it deletes users' data), and
/// the emptied `offline_*` tables stay for a possible multi-city return.
class LocalDb {
  static Database? _db;
  static String? _dbPath;

  static Future<Database> instance() async {
    // Reopen if the file went away (app data cleared; tests use a fresh dir).
    if (_db != null && File(_dbPath!).existsSync()) return _db!;
    await _db?.close();
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'rotransit.db');
    _dbPath = dbPath;
    _db = await openDatabase(
      dbPath,
      version: 6,
      onCreate: (db, version) async => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await _createOfflineTransitTables(db);
        }
        if (oldVersion < 4 && oldVersion >= 3) {
          await db.execute(
            'ALTER TABLE offline_transit_meta ADD COLUMN pack_version TEXT NOT NULL DEFAULT \'\'',
          );
        }
        if (oldVersion < 5) {
          await db.execute('DROP TABLE IF EXISTS sync_queue');
        }
        if (oldVersion < 6) {
          // Search history and the never-used saved_buses table are gone.
          // saved_routes (old journeys) is left alone: it has no reader any
          // more, but dropping it would delete users' data for good.
          await db.execute('DROP TABLE IF EXISTS recent_searches');
          await db.execute('DROP TABLE IF EXISTS saved_buses');
        }
      },
    );
    return _db!;
  }

  /// Opens the DB (so pending migrations run) and empties the offline tables.
  /// Nothing writes them any more (the server pack download is gone), so any
  /// rows are stale leftovers from older versions. saved_routes is kept.
  static Future<void> openAndClearStaleOfflineData() async {
    final db = await instance();
    await db.transaction((txn) async {
      for (final table in const [
        'offline_transit_meta',
        'offline_bus_lines',
        'offline_route_stops',
        'offline_timetables',
      ]) {
        await txn.delete(table);
      }
    });
  }

  static Future<void> _createTables(Database db) async {
    await _createOfflineTransitTables(db);
  }

  static Future<void> _createOfflineTransitTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_transit_meta(
        city_id TEXT PRIMARY KEY,
        anchor_monday_iso TEXT NOT NULL,
        downloaded_at_iso TEXT NOT NULL,
        pack_version TEXT NOT NULL DEFAULT '',
        schema_version INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_bus_lines(
        city_id TEXT PRIMARY KEY,
        buses_json TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_route_stops(
        city_id TEXT NOT NULL,
        route_id TEXT NOT NULL,
        direction_id TEXT NOT NULL,
        stops_json TEXT NOT NULL,
        PRIMARY KEY (city_id, route_id, direction_id)
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_timetables(
        city_id TEXT NOT NULL,
        route_id TEXT NOT NULL,
        stop_id TEXT NOT NULL,
        direction_id TEXT NOT NULL,
        day_kind TEXT NOT NULL,
        timetable_json TEXT NOT NULL,
        PRIMARY KEY (city_id, route_id, stop_id, direction_id, day_kind)
      );
    ''');
  }
}
