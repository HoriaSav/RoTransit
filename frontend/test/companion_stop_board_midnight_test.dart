import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/pack_test_env.dart';

// Fixtures picked from the bundled RATBV pack (pack_version 7d8dad3a…):
// - node/11016370557: Mon–Fri first trip 05:20:35; Sat and Sun first trip
//   08:47:35. No trips between 07:47:35 and 08:47:35 on weekdays.
// - node/11671674450: a Mon–Fri-only 24:05:00 trip (line 36, direction 1);
//   no Saturday/Sunday trips after 23:30.
const _earlyStop = 'node/11016370557';
const _lateStop = 'node/11671674450';

List<String> _times(List<StopBoardDeparture> board) =>
    [for (final d in board) d.departureTime];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = usePackTestEnv(prefix: 'rotransit_midnight_');
  final catalog = CompanionCatalog.instance;

  group('stop board window crossing midnight uses the next day\'s service', () {
    test('Friday 23:50 does not show Friday\'s own early-morning trips',
        () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 10, 2, 23, 50), // Friday
        windowMinutes: 360, // until Saturday 05:50
      );
      expect(_times(board), isNot(contains('05:20:35')),
          reason: 'Saturday service starts at 08:47:35 at this stop');
    });

    test('control: Thursday 23:50 shows Friday\'s 05:20:35 trip', () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 10, 1, 23, 50), // Thursday
        windowMinutes: 360,
      );
      expect(_times(board), contains('05:20:35'));
    });

    test('next day is a holiday: Thursday 24 Dec 23:50 uses Sunday service',
        () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 12, 24, 23, 50),
        windowMinutes: 360,
      );
      expect(_times(board), isNot(contains('05:20:35')),
          reason: '25 Dec runs Sunday service (day_overrides)');
    });

    test('results are ordered by real time across midnight', () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 10, 1, 20, 0), // Thursday evening
        windowMinutes: 600, // until Friday 06:00
      );
      int effective(String raw, bool nextDay) =>
          CompanionCatalog.timeToMinutes(raw)! + (nextDay ? 24 * 60 : 0);
      // Next-day trips are the ones below 20:00 as clock time.
      final mins = [
        for (final t in _times(board))
          effective(t, CompanionCatalog.timeToMinutes(t)! < 20 * 60)
      ];
      final sorted = [...mins]..sort();
      expect(mins, sorted);
      expect(_times(board).last, '05:20:35');
    });
  });

  group('stop board just after midnight includes the previous service day', () {
    test('Saturday 00:00 shows Friday\'s 24:05 trip', () async {
      final board = await catalog.stopBoard(
        stopId: _lateStop,
        from: DateTime(2026, 10, 3), // Saturday 00:00
        windowMinutes: 30,
      );
      expect(_times(board), contains('24:05:00'));
      final dep = board.firstWhere((d) => d.departureTime == '24:05:00');
      expect(dep.shortName, '36');
      expect(dep.directionId, '1');
    });

    test(
        'previous day was a holiday: Saturday 26 Dec 00:00 has no weekday '
        '24:05 trip', () async {
      final board = await catalog.stopBoard(
        stopId: _lateStop,
        from: DateTime(2026, 12, 26),
        windowMinutes: 30,
      );
      expect(_times(board), isNot(contains('24:05:00')));
    });

    test('a 24:05 trip is not shown at 00:10 (already left)', () async {
      final board = await catalog.stopBoard(
        stopId: _lateStop,
        from: DateTime(2026, 9, 29, 0, 10), // Tuesday 00:10
        windowMinutes: 30,
      );
      expect(_times(board), isNot(contains('24:05:00')));
    });
  });

  group('holidays run Sunday service on the stop board', () {
    test('Friday 25 Dec 08:30 shows the Sunday 08:47:35 trip', () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 12, 25, 8, 30),
        windowMinutes: 30,
      );
      expect(_times(board), contains('08:47:35'));
    });

    test('control: an ordinary Friday 08:30 has no trip in that window',
        () async {
      final board = await catalog.stopBoard(
        stopId: _earlyStop,
        from: DateTime(2026, 10, 2, 8, 30),
        windowMinutes: 30,
      );
      expect(_times(board), isEmpty);
    });

    test('every day_overrides row in the pack is honoured', () async {
      // Independent copy of the bundled pack (the catalog singleton may
      // have extracted into an earlier test's temp dir).
      final copy = File('${docs().path}/oracle.sqlite')
        ..writeAsBytesSync(gzip.decode(
            File('assets/data/brasov_companion.sqlite.gz').readAsBytesSync()));
      final db = await databaseFactoryFfi.openDatabase(
        copy.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(db.close);
      final rows = await db.query('day_overrides');
      expect(rows, isNotEmpty);
      for (final r in rows) {
        final d = DateTime.parse(r['service_date'] as String);
        expect(await catalog.serviceDayKindFor(d), r['day_kind'],
            reason: 'override for ${r['service_date']}');
      }
      // A date with no override falls back to the weekday.
      expect(
          await catalog.serviceDayKindFor(DateTime(2026, 10, 3)), 'SATURDAY');
    });
  });
}
