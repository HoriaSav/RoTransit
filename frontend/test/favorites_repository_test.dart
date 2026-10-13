import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/favorites/data/favorite_stops_repository.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _livada = StopSearchItem(
  stopId: 'node/11016370557',
  name: 'Livada Poștei',
  lat: 45.6441,
  lon: 25.5883,
);
const _centru = StopSearchItem(
  stopId: 'node/11671674450',
  name: 'Centrul Civic',
  lat: 45.65,
  lon: 25.60,
);
const _line5 = BusLine(
  routeId: 'rt-5',
  shortName: '5',
  longName: 'Roman – Stadionul Municipal',
  mode: 'bus',
);
const _line36 = BusLine(
  routeId: 'rt-36',
  shortName: '36',
  longName: 'Livada Poștei – Gara',
  mode: 'bus',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('favorite stops', () {
    test('toggle adds, a second toggle removes', () async {
      final repo = FavoriteStopsRepository();
      expect(await repo.listStops(), isEmpty);

      await repo.toggleStop(_livada);
      expect((await repo.listStops()).map((s) => s.stopId), [_livada.stopId]);
      expect(await repo.isStopFavorite(_livada.stopId), isTrue);

      await repo.toggleStop(_livada);
      expect(await repo.listStops(), isEmpty);
      expect(await repo.isStopFavorite(_livada.stopId), isFalse);
    });

    test('removing one stop keeps the others, in insertion order', () async {
      final repo = FavoriteStopsRepository();
      await repo.toggleStop(_livada);
      await repo.toggleStop(_centru);
      await repo.toggleStop(_livada);
      await repo.toggleStop(_livada);
      expect((await repo.listStops()).map((s) => s.stopId),
          [_centru.stopId, _livada.stopId]);
    });

    test('a stop persists with all fields across repository instances',
        () async {
      await FavoriteStopsRepository().toggleStop(_livada);
      final back = (await FavoriteStopsRepository().listStops()).single;
      expect(back.stopId, _livada.stopId);
      expect(back.name, _livada.name);
      expect(back.lat, _livada.lat);
      expect(back.lon, _livada.lon);
    });

    test('a corrupt stored entry is skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'rotransit_favorite_stops_v1': [
          'not json',
          '{"stopId":"node/1","name":"Ok","lat":1,"lon":2}',
        ],
      });
      final list = await FavoriteStopsRepository().listStops();
      expect(list.map((s) => s.stopId), ['node/1']);
    });
  });

  group('favorite lines', () {
    test('toggle adds, a second toggle removes', () async {
      final repo = FavoriteStopsRepository();
      await repo.toggleLine(_line5);
      expect((await repo.listLines()).map((l) => l.routeId), ['rt-5']);
      await repo.toggleLine(_line5);
      expect(await repo.listLines(), isEmpty);
    });

    test('lines are keyed by routeId and do not affect stops', () async {
      final repo = FavoriteStopsRepository();
      await repo.toggleStop(_livada);
      await repo.toggleLine(_line5);
      await repo.toggleLine(_line36);
      await repo.toggleLine(_line5);
      expect((await repo.listLines()).map((l) => l.routeId), ['rt-36']);
      expect((await repo.listStops()).single.stopId, _livada.stopId);
    });

    test('a line persists with all fields across repository instances',
        () async {
      await FavoriteStopsRepository().toggleLine(_line36);
      final back = (await FavoriteStopsRepository().listLines()).single;
      expect(back.routeId, _line36.routeId);
      expect(back.shortName, _line36.shortName);
      expect(back.longName, _line36.longName);
      expect(back.mode, _line36.mode);
    });
  });
}
