import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';

// The board window is measured in wall-clock minutes (stopBoard compares
// departure_time minutes against from.hour * 60 + from.minute + window), so
// the sparse-stop cap must also be wall-clock minutes until 04:00.
final bool _zoneHasDst = DateTime(2026, 10, 24, 12).timeZoneOffset !=
    DateTime(2026, 10, 26, 12).timeZoneOffset;

void main() {
  test('ordinary night: 23:00 is 300 wall-clock minutes before 04:00', () {
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 14, 23)), 300);
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 15, 2, 30)), 90);
  });

  test(
      'fall-back night (Sat 24 Oct 2026 23:00): cap is 300 wall-clock '
      'minutes, so the board does not run past 04:00 into Sunday', () {
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 24, 23)), 300);
  }, skip: _zoneHasDst ? false : 'run with TZ=Europe/Bucharest');

  test(
      'spring-forward night (Sat 28 Mar 2026 23:00): cap is 300 wall-clock '
      'minutes, so the board still reaches 04:00', () {
    expect(minutesUntilServiceDayEnd(DateTime(2026, 3, 28, 23)), 300);
  }, skip: _zoneHasDst ? false : 'run with TZ=Europe/Bucharest');
}
