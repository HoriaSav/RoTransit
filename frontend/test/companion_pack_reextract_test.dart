import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/pack_manifest.dart';
import 'support/pack_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_reextract_');

  test('an app update with a new pack_version replaces the extracted pack',
      () async {
    // Simulate an install that extracted an older pack.
    final dir = Directory('${docs().path}/companion')..createSync();
    final dbPath = '${dir.path}/brasov_companion.sqlite';
    final old = await databaseFactoryFfi.openDatabase(dbPath);
    await old.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
    await old.insert('meta', {'key': 'pack_version', 'value': 'old-pack'});
    await old.insert('meta', {'key': 'data_as_of', 'value': '2020-01-01'});
    await old.close();
    File('${dir.path}/brasov_companion.asset_rev')
        .writeAsStringSync('old-pack');

    final meta = await CompanionCatalog.instance.meta();

    expect(meta.packVersion, bundledPackVersion(),
        reason: 'stale extracted pack must be replaced');
    expect(meta.dataAsOf, isNot('2020-01-01'));
    expect(
      File('${dir.path}/brasov_companion.asset_rev').readAsStringSync().trim(),
      bundledPackVersion(),
    );
    expect((await CompanionCatalog.instance.listBuses()).length, 84);
  });
}
