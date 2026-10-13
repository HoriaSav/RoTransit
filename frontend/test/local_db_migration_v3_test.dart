import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/local/local_db.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_local_db.dart';
import 'support/pack_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_migrate_v3_');

  test('upgrading rotransit.db from v3 to v6 keeps user data', () async {
    SharedPreferences.setMockInitialValues({
      'rotransit_favorite_stops_v1': ['{"id":"node/1","name":"Livada Poștei"}'],
      'rotransit_favorite_lines_v1': ['{"id":"5"}'],
    });
    await seedLegacyLocalDb('${docs().path}/rotransit.db', 3);

    final db = await LocalDb.instance();

    expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), 6);
    final tables = await tableNames(db);
    expect(
        tables,
        containsAll(<String>[
          'saved_routes',
          'offline_transit_meta',
          'offline_bus_lines',
          'offline_route_stops',
          'offline_timetables',
        ]));
    expect(tables, isNot(contains('recent_searches')));
    expect(tables, isNot(contains('saved_buses')));
    expect(tables, isNot(contains('sync_queue')));

    final routes = await db.query('saved_routes');
    expect(routes, hasLength(1));
    expect(routes.single['label'], 'Home to work');

    final metaCols =
        (await db.rawQuery('PRAGMA table_info(offline_transit_meta)'))
            .map((r) => r['name'])
            .toSet();
    expect(metaCols, contains('pack_version'));
    final meta = await db.query('offline_transit_meta');
    expect(meta.single['city_id'], 'brasov');
    expect(meta.single['pack_version'], '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('rotransit_favorite_stops_v1'), hasLength(1));
    expect(prefs.getStringList('rotransit_favorite_lines_v1'), hasLength(1));
  });
}
