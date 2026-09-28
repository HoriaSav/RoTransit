import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';

import 'support/pack_test_env.dart';

// Brașov (Europe/Bucharest) leaves summer time on Sunday 25 Oct 2026 at
// 04:00 local, so that Sunday is 25 hours long. Adding a 24-hour Duration to
// Sunday midnight lands on Sunday 23:00, not on Monday.
//
// These checks only mean something when the test runs in a zone with that
// transition (run with TZ=Europe/Bucharest); elsewhere they are skipped.
//
// node/11016370557: Mon–Fri first trip 05:20:35, Sat/Sun first trip 08:47:35.
const _earlyStop = 'node/11016370557';

bool get _zoneHasOct25Transition =>
    DateTime(2026, 10, 25).add(const Duration(days: 1)).day != 26;

List<String> _times(List<StopBoardDeparture> board) =>
    [for (final d in board) d.departureTime];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePackTestEnv(prefix: 'rotransit_dst_');
  final catalog = CompanionCatalog.instance;
  final skip = _zoneHasOct25Transition
      ? false
      : 'local time zone has no DST change on 25 Oct 2026; '
          'run with TZ=Europe/Bucharest';

  test('DST night: Sunday 25 Oct 23:50 shows Monday\'s 05:20:35 trip',
      () async {
    final board = await catalog.stopBoard(
      stopId: _earlyStop,
      from: DateTime(2026, 10, 25, 23, 50), // Sunday, 25-hour day
      windowMinutes: 360, // until Monday 05:50
    );
    expect(_times(board), contains('05:20:35'),
        reason: 'the day after Sunday 25 Oct is Monday 26 Oct (Mon–Fri '
            'service), not Sunday again');
  }, skip: skip);

  test('control: an ordinary Sunday 23:50 (18 Oct) shows Monday\'s 05:20:35',
      () async {
    final board = await catalog.stopBoard(
      stopId: _earlyStop,
      from: DateTime(2026, 10, 18, 23, 50),
      windowMinutes: 360,
    );
    expect(_times(board), contains('05:20:35'));
  });

  test(
      'DST night: Monday 26 Oct 00:00 still treats Sunday as the previous '
      'service day (no weekday 05:20 carried over)', () async {
    final board = await catalog.stopBoard(
      stopId: _earlyStop,
      from: DateTime(2026, 10, 26, 0, 0),
      windowMinutes: 360,
    );
    // Monday's own 05:20:35 is inside the window exactly once.
    expect(_times(board).where((t) => t == '05:20:35'), hasLength(1));
  }, skip: skip);
}
