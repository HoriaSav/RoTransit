import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';

void main() {
  test('dayKindFor maps weekdays', () {
    expect(CompanionCatalog.dayKindFor(DateTime(2026, 9, 24)), 'MONFRI'); // Thu
    expect(CompanionCatalog.dayKindFor(DateTime(2026, 9, 26)), 'SATURDAY');
    expect(CompanionCatalog.dayKindFor(DateTime(2026, 9, 27)), 'SUNDAY');
  });

  test('timeToMinutes parses HH:MM:SS', () {
    expect(CompanionCatalog.timeToMinutes('05:42:00'), 5 * 60 + 42);
    expect(CompanionCatalog.minutesToHhMm(5 * 60 + 42), '05:42');
  });
}
