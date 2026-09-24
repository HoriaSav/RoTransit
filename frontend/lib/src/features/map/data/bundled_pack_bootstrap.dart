import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../saved/state/saved_providers.dart';
import '../../shell/state/navigation_provider.dart';
import 'companion_catalog.dart';

void _syncBrasovCityContext(ProviderContainer container) {
  container.read(searchMapStateProvider.notifier).setCityContext(
        cityId: kBrasovCityId,
        cityName: kBrasovCityName,
      );
}

void _syncBrasovCityContextRef(WidgetRef ref) {
  ref.read(searchMapStateProvider.notifier).setCityContext(
        cityId: kBrasovCityId,
        cityName: kBrasovCityName,
      );
}

/// Seeds the bundled Brașov pack into local offline meta on first launch.
Future<void> ensureBundledBrasovPack(WidgetRef ref) async {
  final cache = ref.read(offlineTransitCacheRepositoryProvider);
  final catalog = ref.read(companionCatalogProvider);
  final meta = await catalog.meta();
  final existing = await cache.getMetaForCity(meta.cityId);
  if (existing == null ||
      existing.packVersion.isEmpty ||
      existing.packVersion != meta.packVersion) {
    await catalog.mirrorMetaIntoLocalOfflineCache(cache.applyOfflinePackJson);
    ref.read(offlinePackRevisionProvider.notifier).state++;
  }
  // City context sync belongs outside FutureProvider build (see saved_providers).
  _syncBrasovCityContextRef(ref);
}

/// Non-WidgetRef variant for [main] / ProviderContainer.
Future<void> ensureBundledBrasovPackWithContainer(
    ProviderContainer container) async {
  final cache = container.read(offlineTransitCacheRepositoryProvider);
  final catalog = container.read(companionCatalogProvider);
  final meta = await catalog.meta();
  final existing = await cache.getMetaForCity(meta.cityId);
  if (existing == null ||
      existing.packVersion.isEmpty ||
      existing.packVersion != meta.packVersion) {
    await catalog.mirrorMetaIntoLocalOfflineCache(cache.applyOfflinePackJson);
    container.read(offlinePackRevisionProvider.notifier).state++;
  }
  _syncBrasovCityContext(container);
}
