import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../local/local_db.dart';
import '../../shell/state/navigation_provider.dart';
import 'companion_catalog.dart';

/// Sets Brașov as the city context and opens the bundled pack (on first launch
/// or after an app update this extracts the asset, off the UI isolate).
///
/// Brașov screens read [CompanionCatalog] directly, so nothing is mirrored
/// into the local offline tables. `rotransit.db` is still opened here so its
/// migrations run on upgrade, and stale offline rows are cleared.
Future<void> ensureBundledBrasovPackWithContainer(
    ProviderContainer container) async {
  container.read(searchMapStateProvider.notifier).setCityContext(
        cityId: kBrasovCityId,
        cityName: kBrasovCityName,
      );
  try {
    await container.read(companionCatalogProvider).meta();
  } finally {
    // Independent of the pack: a pack failure must not skip the migration.
    try {
      await LocalDb.openAndClearStaleOfflineData();
    } catch (e) {
      debugPrint('rotransit.db migration failed: $e');
    }
  }
}
