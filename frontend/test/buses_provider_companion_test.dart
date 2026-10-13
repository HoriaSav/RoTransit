import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('rotransit_buses_provider_');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  test('busesProvider + packInstalled serve Brașov companion offline '
      'with empty cityId (no API fallthrough)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(searchMapStateProvider).cityId, isEmpty);

    final installed =
        await container.read(cityOfflinePackInstalledProvider.future);
    expect(installed, isTrue);

    final buses = await container.read(busesProvider.future);
    expect(buses.length, 84);

    // Still pure during provider builds.
    expect(container.read(searchMapStateProvider).cityId, isEmpty);

    final routeId = buses.first.routeId;
    final stops = await container.read(routeStopsProvider((
      routeId: routeId,
      directionId: '0',
    )).future);
    expect(stops, isNotEmpty);

    final monday = DateTime(2026, 1, 19);
    final board = await container.read(routeTimetableProvider((
      routeId: routeId,
      stopId: stops.first.stopId,
      serviceDate: monday,
      directionId: '0',
    )).future);
    expect(board.departures, isNotEmpty);
  });
}
