import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/state/clock_provider.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/bundled_pack_bootstrap.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/bus_tab.dart';
import 'package:rotransit/src/features/settings/presentation/settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

// "Timetable data ended" on the Timetable tab and in Settings with the clock
// pinned through clockProvider, against the real bundled pack. The last
// service date comes from the pack, so these keep working after a refresh.

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<DateTime> _lastServiceDay(WidgetTester tester) async {
  final range =
      await tester.runAsync(() => CompanionCatalog.instance.feedDateRange());
  expect(range, isNotNull);
  return range!.end;
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required DateTime now,
  String locale = 'en',
}) async {
  final c = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(c.dispose);
  await tester.runAsync(() => ensureBundledBrasovPackWithContainer(c));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  usePackTestEnv(prefix: 'rotransit_feed_ended_clock_');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'RoTransit',
      packageName: 'ro.rotransit',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => CompanionCatalog.instance.reset());

  for (final locale in ['en', 'ro', 'de']) {
    testWidgets(
        '$locale: Timetable tab shows the "data ended" notice the day after '
        'the last service date', (tester) async {
      final end = await _lastServiceDay(tester);
      await _pump(tester, const BusTab(),
          now: DateTime(end.year, end.month, end.day + 1, 8), locale: locale);

      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      expect(find.text(l10n.stopBoardFeedEnded(CompanionCatalog.isoDate(end))),
          findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  }

  testWidgets(
      'Timetable tab shows no "data ended" notice on the last service date',
      (tester) async {
    final end = await _lastServiceDay(tester);
    await _pump(tester, const BusTab(),
        now: DateTime(end.year, end.month, end.day, 23, 59));

    expect(find.textContaining('Timetable data ended'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    // The lines list is there.
    expect(find.text('Urban'), findsOneWidget);
  });

  testWidgets(
      'Timetable tab rechecks on resume: open on the last service date, '
      'resumed just after midnight, the notice appears', (tester) async {
    final end = await _lastServiceDay(tester);
    var now = DateTime(end.year, end.month, end.day, 23, 59);
    final c = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => ensureBundledBrasovPackWithContainer(c));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BusTab()),
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('Timetable data ended'), findsNothing);

    // Backgrounded overnight, resumed at 00:00 the day after the end.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(end.year, end.month, end.day + 1);
    await _settle(tester);
    expect(find.textContaining('Timetable data ended'), findsNothing,
        reason: 'only rechecked on resume');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(
        find.text('Timetable data ended on ${CompanionCatalog.isoDate(end)}. '
            'Update the app to see departures.'),
        findsOneWidget);
  });

  testWidgets(
      "the stop board's own clock wins over clockProvider (last service "
      'date vs pinned day after)', (tester) async {
    final end = await _lastServiceDay(tester);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
        tester,
        StopBoardSheet(
          stop: const StopSearchItem(
              stopId: 'node/8227802075', name: 'Hidro A', lat: 45.6, lon: 25.6),
          clock: () => DateTime(end.year, end.month, end.day, 8),
        ),
        now: DateTime(end.year, end.month, end.day + 1, 8));

    expect(find.textContaining('Timetable data ended'), findsNothing);
    expect(find.textContaining(' → '), findsWidgets);
  });

  testWidgets(
      'Settings shows the "data ended" row the day after the last service '
      'date (clock pinned)', (tester) async {
    final end = await _lastServiceDay(tester);
    await _pump(tester, const SettingsTab(),
        now: DateTime(end.year, end.month, end.day + 1, 8));

    expect(find.text('Brașov data as of'), findsOneWidget);
    expect(
        find.text('Timetable data ended on ${CompanionCatalog.isoDate(end)}. '
            'Update the app to see departures.'),
        findsOneWidget);
  });

  testWidgets(
      'Settings shows no "data ended" row on the last service date (clock '
      'pinned)', (tester) async {
    final end = await _lastServiceDay(tester);
    await _pump(tester, const SettingsTab(),
        now: DateTime(end.year, end.month, end.day, 23, 59));

    expect(find.text('Brașov data as of'), findsOneWidget);
    expect(find.textContaining('Timetable data ended'), findsNothing);
  });
}
