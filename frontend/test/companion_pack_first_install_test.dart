import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/branding/operator_branding.dart';
import 'package:rotransit/src/features/map/data/bundled_pack_bootstrap.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';

import 'support/pack_manifest.dart';
import 'support/pack_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_first_install_');

  test(
      'first launch bootstrap extracts the pack, writes the marker and sets '
      'Brașov as the city', () async {
    final dir = Directory('${docs().path}/companion');
    expect(dir.existsSync(), isFalse, reason: 'fresh install');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await ensureBundledBrasovPackWithContainer(container);

    final db = File('${dir.path}/brasov_companion.sqlite');
    final marker = File('${dir.path}/brasov_companion.asset_rev');
    expect(db.existsSync(), isTrue);
    expect(db.lengthSync(), greaterThan(20 * 1024 * 1024),
        reason: 'the ~27 MB decompressed pack');
    expect(marker.readAsStringSync().trim(), bundledPackVersion());

    final state = container.read(searchMapStateProvider);
    expect(state.cityId, kBrasovCityId);
    expect(state.cityName, kBrasovCityName);

    final meta = await CompanionCatalog.instance.meta();
    expect(meta.packVersion, bundledPackVersion());
    expect(meta.dataAsOf, bundledDataAsOf());
  });
}
