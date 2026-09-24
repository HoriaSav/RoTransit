import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/domain/route_models.dart';

const _kFavoriteStopsKey = 'rotransit_favorite_stops_v1';
const _kFavoriteLinesKey = 'rotransit_favorite_lines_v1';

final favoriteStopsRepositoryProvider = Provider<FavoriteStopsRepository>((ref) {
  return FavoriteStopsRepository();
});

final favoriteStopsRevisionProvider = StateProvider<int>((ref) => 0);

final favoriteStopsProvider = FutureProvider<List<StopSearchItem>>((ref) async {
  ref.watch(favoriteStopsRevisionProvider);
  return ref.read(favoriteStopsRepositoryProvider).listStops();
});

final favoriteLinesRevisionProvider = StateProvider<int>((ref) => 0);

final favoriteLinesProvider = FutureProvider<List<BusLine>>((ref) async {
  ref.watch(favoriteLinesRevisionProvider);
  return ref.read(favoriteStopsRepositoryProvider).listLines();
});

class FavoriteStopsRepository {
  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<List<StopSearchItem>> listStops() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_kFavoriteStopsKey) ?? const [];
    final out = <StopSearchItem>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        out.add(StopSearchItem.fromJson(map));
      } catch (_) {}
    }
    return out;
  }

  Future<bool> isStopFavorite(String stopId) async {
    final list = await listStops();
    return list.any((s) => s.stopId == stopId);
  }

  Future<void> toggleStop(StopSearchItem stop) async {
    final prefs = await _prefs;
    final list = await listStops();
    final idx = list.indexWhere((s) => s.stopId == stop.stopId);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(stop);
    }
    await prefs.setStringList(
      _kFavoriteStopsKey,
      list
          .map(
            (s) => jsonEncode({
              'stopId': s.stopId,
              'name': s.name,
              'lat': s.lat,
              'lon': s.lon,
            }),
          )
          .toList(),
    );
  }

  Future<List<BusLine>> listLines() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_kFavoriteLinesKey) ?? const [];
    final out = <BusLine>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        out.add(BusLine.fromJson(map));
      } catch (_) {}
    }
    return out;
  }

  Future<bool> isLineFavorite(String routeId) async {
    final list = await listLines();
    return list.any((l) => l.routeId == routeId);
  }

  Future<void> toggleLine(BusLine line) async {
    final prefs = await _prefs;
    final list = await listLines();
    final idx = list.indexWhere((l) => l.routeId == line.routeId);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(line);
    }
    await prefs.setStringList(
      _kFavoriteLinesKey,
      list
          .map(
            (l) => jsonEncode({
              'routeId': l.routeId,
              'shortName': l.shortName,
              'longName': l.longName,
              'mode': l.mode,
            }),
          )
          .toList(),
    );
  }
}
