import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';

import 'support/pack_test_env.dart';

// node/267042578 (Liceul Meșotă): TE14, a student-only line, leaves at
// 07:06:00 on Mon–Fri; about 36 regular departures also fall in 07:00–07:30.
const _schoolStop = 'node/267042578';

List<String> _routes(List<StopBoardDeparture> board) =>
    [for (final d in board) d.routeId];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePackTestEnv(prefix: 'rotransit_school_te_');
  final catalog = CompanionCatalog.instance;

  test('control: on a school day (Wed 14 Oct 2026) TE14 is on the board',
      () async {
    final board = await catalog.stopBoard(
      stopId: _schoolStop,
      from: DateTime(2026, 10, 14, 7, 0),
      windowMinutes: 30,
    );
    expect(_routes(board), contains('TE14'));
  });

  test(
      'feed calendar_dates: TE service is removed on Wed 15 Jul 2026 '
      '(summer break), regular Mon–Fri service still shown', () async {
    final board = await catalog.stopBoard(
      stopId: _schoolStop,
      from: DateTime(2026, 7, 15, 7, 0),
      windowMinutes: 30,
    );
    final routes = _routes(board);
    expect(routes.where((r) => r.startsWith('TE')), isEmpty,
        reason: 'TE lines only run on school days');
    expect(routes.where((r) => !r.startsWith('TE')), isNotEmpty,
        reason: 'a school holiday weekday is still Mon–Fri service');
  });
}
