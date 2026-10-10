import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/bundled_pack_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_local_db.dart';
import 'support/pack_test_env.dart';

// The v6 migration must actually run for people upgrading the app. On the
// Brașov path nothing else opens rotransit.db, so the startup bootstrap has
// to. If the fix opens LocalDb somewhere else at startup, point this test at
// that entry point instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_startup_db_');

  test('startup bootstrap upgrades an existing v5 rotransit.db to v6',
      () async {
    SharedPreferences.setMockInitialValues({});
    final path = '${docs().path}/rotransit.db';
    await seedLegacyLocalDb(path, 5);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await ensureBundledBrasovPackWithContainer(container);

    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    addTearDown(db.close);
    final version =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
    expect(version, 6, reason: 'v6 migration never ran');
    final tables = await tableNames(db);
    expect(tables, isNot(contains('recent_searches')),
        reason: 'old search history should be deleted by v6');
    expect(tables, contains('saved_routes'));
  });
}
