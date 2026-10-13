import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/shell/state/bus_line_open_provider.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog implements CompanionCatalog {
  @override
  Future<List<StopBoardDeparture>> stopBoard({
    required String stopId,
    required DateTime from,
    required int windowMinutes,
  }) async =>
      const [
        StopBoardDeparture(
          routeId: '36',
          shortName: '36',
          longName: 'Independenței - Livada Poștei',
          directionId: '1',
          headsign: 'Independenței',
          departureTime: '23:37:00',
          tripId: 't-36-1',
        ),
        StopBoardDeparture(
          routeId: '110',
          shortName: '110',
          longName: 'Barșov - Cristian',
          directionId: '0',
          headsign: 'Cristian',
          departureTime: '23:40:00',
          tripId: 't-110-0',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _stop = StopSearchItem(
  stopId: 'node/11671674450',
  name: 'Ștefan Baciu',
  lat: 45.6,
  lon: 25.6,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> openSheet(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [companionCatalogProvider.overrideWithValue(_FakeCatalog())],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showStopBoardSheet(context, stop: _stop),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(StopBoardSheet), findsOneWidget);
    return c;
  }

  testWidgets(
      'tapping a departure asks Timetable for that line at this stop '
      'in the departure\'s direction, and closes the sheet', (tester) async {
    final c = await openSheet(tester);

    await tester.tap(find.text('Independenței'));
    await tester.pumpAndSettle();

    final req = c.read(pendingOpenBusLineProvider);
    expect(req, isNotNull);
    expect(req!.line.routeId, '36');
    expect(req.stopId, _stop.stopId);
    expect(req.directionId, '1');
    expect(c.read(selectedTabProvider), 1);
    expect(find.byType(StopBoardSheet), findsNothing);
  });

  testWidgets('the direction comes from the tapped row, not the first row',
      (tester) async {
    final c = await openSheet(tester);
    await tester.tap(find.text('Cristian'));
    await tester.pumpAndSettle();
    final req = c.read(pendingOpenBusLineProvider)!;
    expect(req.line.routeId, '110');
    expect(req.directionId, '0');
    expect(req.stopId, _stop.stopId);
  });
}
