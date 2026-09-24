import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/features/map/data/bundled_pack_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FMTCObjectBoxBackend().initialise();
  } catch (_) {
    // Map still works online even if tile cache backend fails.
  }
  final container = ProviderContainer();
  try {
    await ensureBundledBrasovPackWithContainer(container);
  } catch (_) {
    // Companion UI can still open the asset DB on demand.
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RoTransitApp(),
    ),
  );
}
