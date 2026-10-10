import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('rotransit_companion_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDocs.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    // Each test gets a fresh documents dir, so drop the catalog's open handle.
    await CompanionCatalog.instance.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  test('companion pack opens: 84 lines and real day boards offline', () async {
    final catalog = CompanionCatalog.instance;
    final meta = await catalog.meta();
    expect(meta.cityId, isNotEmpty);
    expect(meta.packVersion, isNotEmpty);

    final buses = await catalog.listBuses();
    expect(buses.length, 84);

    final routeId = buses.first.routeId;
    final stops = await catalog.routeStops(routeId: routeId, directionId: '0');
    expect(stops, isNotEmpty, reason: 'line must have stops for board');

    final stopId = stops.first.stopId;
    final monday = DateTime(2026, 1, 19);
    final saturday = monday.add(const Duration(days: 5));
    final sunday = monday.add(const Duration(days: 6));

    final mon = await catalog.timetable(
      routeId: routeId,
      stopId: stopId,
      serviceDate: monday,
      directionId: '0',
    );
    final sat = await catalog.timetable(
      routeId: routeId,
      stopId: stopId,
      serviceDate: saturday,
      directionId: '0',
    );
    final sun = await catalog.timetable(
      routeId: routeId,
      stopId: stopId,
      serviceDate: sunday,
      directionId: '0',
    );

    expect(mon.departures, isNotEmpty,
        reason: 'MONFRI board must show times from local pack');
    expect(CompanionCatalog.dayKindFor(monday), 'MONFRI');
    expect(CompanionCatalog.dayKindFor(saturday), 'SATURDAY');
    expect(CompanionCatalog.dayKindFor(sunday), 'SUNDAY');
    expect(sat.departures, isNotNull);
    expect(sun.departures, isNotNull);
  });

  test('public holidays from calendar_dates use the Sunday schedule', () async {
    final catalog = CompanionCatalog.instance;
    // Friday 25 Dec 2026 runs Sunday services in the RATBV feed.
    expect(await catalog.serviceDayKindFor(DateTime(2026, 12, 25)), 'SUNDAY');
    expect(await catalog.serviceDayKindFor(DateTime(2026, 12, 23)), 'MONFRI');
  });

  test('stop board after midnight includes the previous day\'s late trips',
      () async {
    // Monday service has a 24:05 departure here; on Tuesday 00:00 it is
    // five minutes away.
    final board = await CompanionCatalog.instance.stopBoard(
      stopId: 'node/11671674450',
      from: DateTime(2026, 9, 29),
      windowMinutes: 30,
    );
    expect(board.map((d) => d.departureTime), contains('24:05:00'));
  });
}
