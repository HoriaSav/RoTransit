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
      version: 2,
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
      CREATE TABLE sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
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
  }
}
