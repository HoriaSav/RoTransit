import 'dart:async';

import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

final _ready = Completer<bool>();

/// True once the map tile cache backend is up; false if it failed (tiles then
/// come from the network). Never completes if [initTileCacheBackend] is not
/// called (tests), which simply keeps network tiles.
Future<bool> get tileCacheReady => _ready.future;

/// Started after the first frame so opening the cache never delays startup.
Future<void> initTileCacheBackend() async {
  if (_ready.isCompleted) return;
  try {
    await FMTCObjectBoxBackend().initialise();
    _ready.complete(true);
  } catch (_) {
    _ready.complete(false);
  }
}
