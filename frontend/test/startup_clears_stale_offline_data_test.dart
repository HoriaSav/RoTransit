import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/bundled_pack_bootstrap.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/local/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_local_db.dart';
import 'support/pack_test_env.dart';

class _BrokenPack implements CompanionCatalog {
  @override
  Future<CompanionPackMeta> meta() async => throw StateError('pack broken');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_clear_offline_');

  test('startup empties the old pack mirror but keeps saved_routes', () async {
    SharedPreferences.setMockInitialValues({});
    await seedLegacyLocalDb('${docs().path}/rotransit.db', 4);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await ensureBundledBrasovPackWithContainer(container);

    final db = await LocalDb.instance();
    expect(await db.query('offline_transit_meta'), isEmpty);
    expect(await db.query('saved_routes'), hasLength(1));
  });

  test('a broken pack does not skip the rotransit.db migration', () async {
    SharedPreferences.setMockInitialValues({});
    await seedLegacyLocalDb('${docs().path}/rotransit.db', 4);

    final container = ProviderContainer(overrides: [
      companionCatalogProvider.overrideWithValue(_BrokenPack()),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        ensureBundledBrasovPackWithContainer(container), throwsStateError);

    final db = await LocalDb.instance();
    expect(await db.rawQuery('PRAGMA user_version'), [
      {'user_version': 6}
    ]);
    expect(await db.query('offline_transit_meta'), isEmpty);
  });
}
