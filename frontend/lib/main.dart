import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/map/tile_cache_backend.dart';
import 'src/features/map/data/bundled_pack_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RoTransitApp(),
    ),
  );
  // Open the bundled pack after the first frame; screens show their own
  // loading state until it is ready.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // The map uses network tiles until the tile cache is ready.
    unawaited(initTileCacheBackend());
    ensureBundledBrasovPackWithContainer(container)
        .catchError((Object e, StackTrace st) {
      // Companion UI retries opening the asset DB on demand.
      debugPrint('Bundled pack bootstrap failed: $e\n$st');
    });
  });
}
