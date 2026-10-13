import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One departure every [everyMinutes] from [from]; records each window asked.
class _FakeCatalog implements CompanionCatalog {
  _FakeCatalog({required this.everyMinutes});

  final int everyMinutes;
  final windows = <int>[];
  final starts = <DateTime>[];

  @override
  Future<({DateTime start, DateTime end})?> feedDateRange() async =>
      (start: DateTime(2026, 1, 23), end: DateTime(2027, 5, 23));

  @override
  Future<List<StopBoardDeparture>> stopBoard({
    required String stopId,
    required DateTime from,
    required int windowMinutes,
  }) async {
    windows.add(windowMinutes);
    starts.add(from);
    final start = from.hour * 60 + from.minute;
    return [
      for (var m = 0; m < windowMinutes; m += everyMinutes)
        StopBoardDeparture(
          routeId: 'R$m',
          shortName: '$m',
          longName: '',
          directionId: '0',
          headsign: 'H$m',
          departureTime: CompanionCatalog.minutesToHhMm(start + m),
          tripId: 't$m',
          firstStopName: 'Livada Poștei',
          lastStopName: 'Independenței $m',
          minutesAfterStart: m,
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _stop = StopSearchItem(stopId: 's1', name: 'Test stop', lat: 45.6, lon: 25.6);

Future<void> _pumpSheet(
  WidgetTester tester,
  CompanionCatalog catalog, {
  required DateTime now,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [companionCatalogProvider.overrideWithValue(catalog)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StopBoardSheet(stop: _stop, clock: () => now)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rows show both ends of the ride', (tester) async {
    await _pumpSheet(tester, _FakeCatalog(everyMinutes: 5),
        now: DateTime(2026, 10, 1, 8));
    expect(find.text('Livada Poștei → Independenței 0'), findsOneWidget);
  });

  testWidgets('no "Scheduled" word on the board', (tester) async {
    await _pumpSheet(tester, _FakeCatalog(everyMinutes: 5),
        now: DateTime(2026, 10, 1, 8));
    expect(find.textContaining('Scheduled'), findsNothing);
    expect(find.text('Next 30 min'), findsOneWidget);
  });

  testWidgets('sparse stop: widens by 30 min until at least 5 departures',
      (tester) async {
    final catalog = _FakeCatalog(everyMinutes: 20); // 2 per 30 min
    await _pumpSheet(tester, catalog, now: DateTime(2026, 10, 1, 8));
    // One fetch to 04:00 (20 h), then 30 → 2, 60 → 3, 90 → 5.
    expect(catalog.windows, [20 * 60]);
    expect(find.text('Next 90 min'), findsOneWidget);
    expect(find.textContaining('Livada Poștei →'), findsNWidgets(5));
  });

  testWidgets('sparse stop: stops widening when the service day ends',
      (tester) async {
    final catalog = _FakeCatalog(everyMinutes: 1000); // 1 departure max
    await _pumpSheet(tester, catalog, now: DateTime(2026, 10, 1, 2, 30));
    // Service day ends at 04:00: 90 minutes from 02:30.
    expect(catalog.windows, [90]);
    expect(find.text('Next 90 min'), findsOneWidget);
  });

  test('minutesUntilServiceDayEnd', () {
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 1, 2, 30)), 90);
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 1, 23)), 5 * 60);
    expect(minutesUntilServiceDayEnd(DateTime(2026, 10, 31, 23)), 5 * 60);
  });

  testWidgets('+30 min appends departures and keeps the scroll position',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = _FakeCatalog(everyMinutes: 2); // 15 per 30 min
    await _pumpSheet(tester, catalog, now: DateTime(2026, 10, 1, 8));
    expect(catalog.windows, [20 * 60]);

    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    final before = scrollable.position.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.text('Show next 30 minutes'));
    await tester.pumpAndSettle();

    expect(catalog.windows, [20 * 60, 60]);
    expect(find.text('Next 60 min'), findsOneWidget);
    final after = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    expect(after.pixels, before, reason: 'no jump to top');
    expect(after.maxScrollExtent, greaterThan(before),
        reason: 'new departures were appended below');
  });

  testWidgets('sparse stop: a long window reads "Until 04:00", not minutes',
      (tester) async {
    await _pumpSheet(tester, _FakeCatalog(everyMinutes: 100000),
        now: DateTime(2026, 10, 1, 8));
    expect(find.text('Until 04:00'), findsOneWidget);
    expect(find.textContaining('1200'), findsNothing);
  });

  testWidgets('after the feed ends the board says so instead of going empty',
      (tester) async {
    await _pumpSheet(
      tester,
      _EmptyAfterEnd(_FakeCatalog(everyMinutes: 1)),
      now: DateTime(2027, 6, 1, 8),
    );
    expect(
      find.text('Timetable data ended on 2027-05-23. '
          'Update the app to see departures.'),
      findsOneWidget,
    );
    expect(find.textContaining('No departures'), findsNothing);
  });

  testWidgets('an empty board inside the feed keeps the normal message',
      (tester) async {
    await _pumpSheet(
      tester,
      _EmptyAfterEnd(_FakeCatalog(everyMinutes: 1)),
      now: DateTime(2027, 5, 23, 8),
    );
    expect(find.text('No departures until 04:00'), findsOneWidget);
    expect(find.textContaining('Timetable data ended'), findsNothing);
  });

  testWidgets('back from the background the board restarts at the new time',
      (tester) async {
    var now = DateTime(2026, 10, 1, 8);
    final catalog = _FakeCatalog(everyMinutes: 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [companionCatalogProvider.overrideWithValue(catalog)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StopBoardSheet(stop: _stop, clock: () => now)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(catalog.starts, [DateTime(2026, 10, 1, 8)]);

    now = DateTime(2026, 10, 1, 8, 20);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(catalog.starts.last, DateTime(2026, 10, 1, 8, 20));
    expect(find.text('Livada Poștei → Independenței 0'), findsOneWidget);
  });
}

/// Same fake, but no departures at all (as after the feed's last day).
class _EmptyAfterEnd implements CompanionCatalog {
  _EmptyAfterEnd(this.inner);
  final _FakeCatalog inner;

  @override
  Future<({DateTime start, DateTime end})?> feedDateRange() =>
      inner.feedDateRange();

  @override
  Future<List<StopBoardDeparture>> stopBoard({
    required String stopId,
    required DateTime from,
    required int windowMinutes,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
