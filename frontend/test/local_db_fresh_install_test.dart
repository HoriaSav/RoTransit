import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/local/local_db.dart';
import 'package:sqflite/sqflite.dart';

import 'support/legacy_local_db.dart';
import 'support/pack_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePackTestEnv(prefix: 'rotransit_fresh_db_');

  test('a fresh install creates only the offline tables at v6', () async {
    final db = await LocalDb.instance();
    expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), 6);
    expect(await tableNames(db), {
      'offline_transit_meta',
      'offline_bus_lines',
      'offline_route_stops',
      'offline_timetables',
    });
  });
}
