import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds `rotransit.db` the way older app versions left it on the device.
/// Schemas are copied from git history of lib/src/local/local_db.dart.
Future<void> seedLegacyLocalDb(String path, int version) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE saved_routes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_user_id TEXT NOT NULL,
            city_id TEXT NOT NULL,
            label TEXT,
            route_metadata TEXT NOT NULL,
            created_at TEXT NOT NULL
          );''');
        await db.execute('''
          CREATE TABLE saved_buses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          );''');
        await db.execute('''
          CREATE TABLE sync_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payload TEXT NOT NULL
          );''');
        if (version >= 2) {
          await db.execute('''
            CREATE TABLE recent_searches(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              city_id TEXT NOT NULL, city_name TEXT NOT NULL,
              from_name TEXT NOT NULL, from_lat REAL NOT NULL,
              from_lon REAL NOT NULL, to_name TEXT NOT NULL,
              to_lat REAL NOT NULL, to_lon REAL NOT NULL,
              service_date_iso TEXT NOT NULL,
              service_time_hhmm TEXT NOT NULL, created_at TEXT NOT NULL
            );''');
        }
        if (version >= 3) {
          final packCol =
              version >= 4 ? "pack_version TEXT NOT NULL DEFAULT ''," : '';
          await db.execute('''
            CREATE TABLE offline_transit_meta(
              city_id TEXT PRIMARY KEY,
              anchor_monday_iso TEXT NOT NULL,
              downloaded_at_iso TEXT NOT NULL,
              $packCol
              schema_version INTEGER NOT NULL
            );''');
          await db.execute('''
            CREATE TABLE offline_bus_lines(
              city_id TEXT PRIMARY KEY, buses_json TEXT NOT NULL);''');
          await db.execute('''
            CREATE TABLE offline_route_stops(
              city_id TEXT NOT NULL, route_id TEXT NOT NULL,
              direction_id TEXT NOT NULL, stops_json TEXT NOT NULL,
              PRIMARY KEY (city_id, route_id, direction_id));''');
          await db.execute('''
            CREATE TABLE offline_timetables(
              city_id TEXT NOT NULL, route_id TEXT NOT NULL,
              stop_id TEXT NOT NULL, direction_id TEXT NOT NULL,
              day_kind TEXT NOT NULL, timetable_json TEXT NOT NULL,
              PRIMARY KEY (city_id, route_id, stop_id, direction_id, day_kind));''');
          await db.insert('offline_transit_meta', {
            'city_id': 'brasov',
            'anchor_monday_iso': '2026-01-05',
            'downloaded_at_iso': '2026-01-06T10:00:00Z',
            'schema_version': 1,
          });
        }
        if (version >= 5) {
          await db.execute('DROP TABLE sync_queue');
        }
        await db.insert('saved_routes', {
          'device_user_id': 'device-1',
          'city_id': 'brasov',
          'label': 'Home to work',
          'route_metadata': '{"legs":[]}',
          'created_at': '2026-01-01T08:00:00Z',
        });
        await db.insert('saved_buses', {
          'title': 'Line 5',
          'payload': '{}',
          'created_at': '2026-01-01T08:00:00Z',
        });
      },
    ),
  );
  await db.close();
}

Future<Set<String>> tableNames(Database db) async {
  final rows =
      await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'");
  return rows.map((r) => r['name'] as String).toSet();
}
