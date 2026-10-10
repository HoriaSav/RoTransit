import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';

import 'support/pack_test_env.dart';

// node/11016370557: Mon–Fri first trip 05:20:35 (line 120, Stadionul
// Municipal → Primăria Vulcan); line 120 direction 1 has 12 Mon–Fri and 4
// Sunday departures here.
const _stop = 'node/11016370557';

void main() {
  group('stopBoardServiceDays uses calendar dates (DST-safe)', () {
    List<DateTime> days(DateTime from, int window) => [
          for (final (d, _) in CompanionCatalog.stopBoardServiceDays(from, window))
            d
        ];

    test('Monday after spring-forward (30 Mar 2026): previous day is Sunday',
        () {
      expect(days(DateTime(2026, 3, 30, 0, 10), 30),
          [DateTime(2026, 3, 29), DateTime(2026, 3, 30)]);
    });

    test('fall-back Sunday (25 Oct 2026) 23:50: next day is Monday', () {
      expect(days(DateTime(2026, 10, 25, 23, 50), 30), [
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 26),
      ]);
    });

    test('month and year boundaries', () {
      expect(days(DateTime(2027, 1, 1, 23, 45), 30),
          [DateTime(2026, 12, 31), DateTime(2027, 1, 1), DateTime(2027, 1, 2)]);
    });

    test('offsets: -24h, 0, +24h', () {
      expect(
        [
          for (final (_, o)
              in CompanionCatalog.stopBoardServiceDays(DateTime(2026, 10, 1, 23), 120))
            o
        ],
        [-1440, 0, 1440],
      );
    });
  });

  group('stop board on the real pack', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    usePackTestEnv(prefix: 'rotransit_service_days_');
    final catalog = CompanionCatalog.instance;
    tearDown(catalog.reset);

    test('the window end is exclusive', () async {
      Future<List<String>> times(int window) async => [
            for (final d in await catalog.stopBoard(
                stopId: _stop, from: DateTime(2026, 10, 2, 5), windowMinutes: window))
              d.departureTime
          ];
      expect(await times(20), isNot(contains('05:20:35')));
      expect(await times(21), contains('05:20:35'));
    });

    test('a full-day window lists each trip once (no previous-day copies)',
        () async {
      final board = await catalog.stopBoard(
        stopId: _stop,
        from: DateTime(2026, 10, 3), // Saturday: Sa-Su trips are in 2 tabs
        windowMinutes: 24 * 60,
      );
      final keys = [for (final d in board) '${d.tripId}@${d.departureTime}'];
      expect(keys.toSet().length, keys.length);
      expect(keys, isNotEmpty);
    });

    test('rows carry both ends of the ride', () async {
      final board = await catalog.stopBoard(
        stopId: _stop,
        from: DateTime(2026, 10, 2, 5, 15),
        windowMinutes: 10,
      );
      final dep = board.firstWhere((d) => d.departureTime == '05:20:35');
      expect(dep.firstStopName, 'Stadionul Municipal');
      expect(dep.lastStopName, 'Primăria Vulcan');
    });

    // Leader's decision: the weekly tab shows the regular pattern; only the
    // dated stop board follows calendar_dates. Mon 30 Nov 2026 is a public
    // holiday in the feed (runs the Sunday service).
    test('weekly tab: a holiday Monday week still shows the regular Mon–Fri '
        'schedule', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      Future<int> weekTab(DateTime monday) async => (await container.read(
            routeTimetableProvider((
              routeId: '120',
              stopId: _stop,
              serviceDate: monday,
              directionId: '1',
            )).future,
          ))
              .departures
              .length;
      expect(await weekTab(DateTime(2026, 11, 23)), 12); // ordinary week
      expect(await weekTab(DateTime(2026, 11, 30)), 12); // holiday Monday
    });

    test('...while the dated stop board runs the holiday (Sunday) service',
        () async {
      Future<int> board(DateTime day) async => [
            for (final d in await catalog.stopBoard(
                stopId: _stop, from: DateTime(day.year, day.month, day.day, 4),
                windowMinutes: 24 * 60))
              if (d.routeId == '120' && d.directionId == '1') d
          ].length;
      expect(await board(DateTime(2026, 11, 23)), 12);
      expect(await board(DateTime(2026, 11, 30)), 4);
    });
  });
}
