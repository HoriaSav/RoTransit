import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/data/offline_transit_cache_repository.dart';
import '../../saved/state/saved_providers.dart';
import 'companion_catalog.dart';

/// Seeds the bundled Brașov pack into local offline meta on first launch.
Future<void> ensureBundledBrasovPack(WidgetRef ref) async {
  final cache = ref.read(offlineTransitCacheRepositoryProvider);
  final catalog = ref.read(companionCatalogProvider);
  final meta = await catalog.meta();
  final existing = await cache.getMetaForCity(meta.cityId);
  if (existing != null &&
      existing.packVersion.isNotEmpty &&
      existing.packVersion == meta.packVersion) {
    return;
  }
  await catalog.mirrorMetaIntoLocalOfflineCache(cache.applyOfflinePackJson);
  ref.read(offlinePackRevisionProvider.notifier).state++;
}

/// Non-WidgetRef variant for [main] / ProviderContainer.
Future<void> ensureBundledBrasovPackWithContainer(ProviderContainer container) async {
  final cache = container.read(offlineTransitCacheRepositoryProvider);
  final catalog = container.read(companionCatalogProvider);
  final meta = await catalog.meta();
  final existing = await cache.getMetaForCity(meta.cityId);
  if (existing != null &&
      existing.packVersion.isNotEmpty &&
      existing.packVersion == meta.packVersion) {
    return;
  }
  await catalog.mirrorMetaIntoLocalOfflineCache(cache.applyOfflinePackJson);
  container.read(offlinePackRevisionProvider.notifier).state++;
}
