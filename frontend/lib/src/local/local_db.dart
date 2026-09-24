import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'rotransit.db');
    _db = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, version) async => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS recent_searches(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              city_id TEXT NOT NULL,
              city_name TEXT NOT NULL,
              from_name TEXT NOT NULL,
              from_lat REAL NOT NULL,
              from_lon REAL NOT NULL,
              to_name TEXT NOT NULL,
              to_lat REAL NOT NULL,
              to_lon REAL NOT NULL,
              service_date_iso TEXT NOT NULL,
              service_time_hhmm TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
          ''');
        }
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
      },
    );
    return _db!;
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE saved_routes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_user_id TEXT NOT NULL,
        city_id TEXT NOT NULL,
        label TEXT,
        route_metadata TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE saved_buses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE recent_searches(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        city_id TEXT NOT NULL,
        city_name TEXT NOT NULL,
        from_name TEXT NOT NULL,
        from_lat REAL NOT NULL,
        from_lon REAL NOT NULL,
        to_name TEXT NOT NULL,
        to_lat REAL NOT NULL,
        to_lon REAL NOT NULL,
        service_date_iso TEXT NOT NULL,
        service_time_hhmm TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
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
