import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // App can still run in guest mode without firebase config.
  }
  try {
    await FMTCObjectBoxBackend().initialise();
  } catch (_) {
    // Map still works online even if tile cache backend fails.
  }
  runApp(const ProviderScope(child: RoTransitApp()));
}
