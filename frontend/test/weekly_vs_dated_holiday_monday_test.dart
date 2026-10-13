import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';

import 'support/pack_test_env.dart';

// A week whose Monday is a public holiday (the pack runs Sunday service that
// day). The weekly tab (CompanionCatalog.timetable, given that week's Monday)
// must still show the standard Mon–Fri pattern; the dated stop board for that
// Monday must show the Sunday service. Every holiday Monday in the pack is
// checked; 30 Nov 2026 must be among them.
const _route = '36';
const _stop = 'node/11671674450'; // Ștefan Baciu
const _dir = '1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePackTestEnv(prefix: 'rotransit_holiday_monday_');
  tearDown(() => CompanionCatalog.instance.reset());

  test(
      'holiday Monday: weekly Mon–Fri column is the standard pattern, the '
      'dated board runs Sunday service', () async {
    final catalog = CompanionCatalog.instance;
    final range = (await catalog.feedDateRange())!;

    final holidayMondays = <DateTime>[];
    for (var d = range.start;
        !d.isAfter(range.end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday == DateTime.monday &&
          await catalog.serviceDayKindFor(d) == 'SUNDAY') {
        holidayMondays.add(d);
      }
    }
    expect(holidayMondays, isNotEmpty, reason: 'pack has a holiday Monday');
    expect(holidayMondays, contains(DateTime(2026, 11, 30)));
    for (final h in holidayMondays) {
      final normalMonday = DateTime(h.year, h.month, h.day - 7);
      final sunday = DateTime(h.year, h.month, h.day - 1);
      expect(await catalog.serviceDayKindFor(normalMonday), 'MONFRI');

      Future<List<String>> weekly(DateTime date) async => [
            for (final e in (await catalog.timetable(
                    routeId: _route,
                    stopId: _stop,
                    serviceDate: date,
                    directionId: _dir))
                .departures)
              '${e.departureTime}|${e.tripId}',
          ];

      final onHoliday = await weekly(h);
      final onNormal = await weekly(normalMonday);
      final onSunday = await weekly(sunday);
      expect(onNormal, isNotEmpty);
      expect(onHoliday, onNormal,
          reason: 'weekly Mon–Fri column for the week of $h');
      expect(onHoliday, isNot(onSunday));

      final monFriTrips = {for (final k in onNormal) k.split('|')[1]};
      final sundayTrips = {for (final k in onSunday) k.split('|')[1]};
      final board = [
        for (final d in await catalog.stopBoard(
            stopId: _stop,
            from: DateTime(h.year, h.month, h.day, 5),
            windowMinutes: 19 * 60))
          if (d.routeId == _route && d.directionId == _dir) d.tripId,
      ];
      expect(board, isNotEmpty);
      expect(board.where(monFriTrips.contains), isEmpty,
          reason: 'no Mon–Fri trips on the dated board for $h');
      expect(board.every(sundayTrips.contains), isTrue,
          reason: 'the dated board for $h runs the Sunday trips');
    }
  });
}
