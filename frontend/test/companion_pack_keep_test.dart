import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/pack_manifest.dart';
import 'support/pack_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_keep_');

  test('a normal relaunch with the same pack_version does not re-extract',
      () async {
    // An already-extracted pack whose marker matches the bundled version.
    // The sentinel data_as_of proves the file was not overwritten.
    final dir = Directory('${docs().path}/companion')..createSync();
    final dbPath = '${dir.path}/brasov_companion.sqlite';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
    await db.insert('meta', {'key': 'data_as_of', 'value': 'SENTINEL'});
    await db.close();
    File('${dir.path}/brasov_companion.asset_rev')
        .writeAsStringSync(bundledPackVersion());

    final meta = await CompanionCatalog.instance.meta();
    expect(meta.dataAsOf, 'SENTINEL');
  });
}
