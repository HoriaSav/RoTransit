import 'dart:io';

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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/pack_test_env.dart';

// "Timetable data ended" on the stop board, the Timetable tab and in Settings,
// against the real bundled pack. The last service date comes from the pack
// itself and every "now" is pinned (board clock or clockProvider), so these
// tests keep working when the pack is refreshed and after it ends.
const _hidroA = StopSearchItem(
    stopId: 'node/8227802075', name: 'Hidro A', lat: 45.6, lon: 25.6);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home,
        {String locale = 'en', List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );

Override _pinClock(DateTime now) => clockProvider.overrideWithValue(() => now);

/// Timetable tab with the app's real startup bootstrap and a pinned clock.
Future<void> _pumpTimetable(WidgetTester tester,
    {required DateTime now, String locale = 'en'}) async {
  final c = ProviderContainer(overrides: [_pinClock(now)]);
  addTearDown(c.dispose);
  await tester.runAsync(() => ensureBundledBrasovPackWithContainer(c));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: BusTab()),
    ),
  ));
  await _settle(tester);
}

/// Extracts the real pack, then ends every service on 2026-01-31, the way an
/// old install looks once its timetables have run out.
Future<void> _seedPackEndingJan31(
    WidgetTester tester, Directory Function() docs) async {
  await tester.runAsync(() async {
    await CompanionCatalog.instance.meta();
    final db = await databaseFactoryFfi
        .openDatabase('${docs().path}/companion/brasov_companion.sqlite');
    await db.rawUpdate("UPDATE services SET start_date = '2026-01-23', "
        "end_date = '2026-01-31'");
    await db.rawDelete('DELETE FROM service_exceptions '
        "WHERE exception_type = 1 AND service_date > '2026-01-31'");
    await db.close();
  });
}

Future<DateTime> _lastServiceDay(WidgetTester tester) async {
  final range =
      await tester.runAsync(() => CompanionCatalog.instance.feedDateRange());
  expect(range, isNotNull);
  return range!.end;
}

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

void main() {
  final docs = usePackTestEnv(prefix: 'rotransit_feed_ended_');
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
        '$locale: the day after the last service date the board says the '
        'timetable data ended and shows no departures', (tester) async {
      final end = await _lastServiceDay(tester);
      final now = DateTime(end.year, end.month, end.day + 1, 8);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
          StopBoardSheet(stop: _hidroA, clock: () => now),
          locale: locale));
      await _settle(tester);

      final l10n = await _l10n(locale);
      expect(find.text(l10n.stopBoardFeedEnded(CompanionCatalog.isoDate(end))),
          findsOneWidget);
    });
  }

  testWidgets(
      'on the last service date the board still lists departures and does '
      'not say the data ended', (tester) async {
    final end = await _lastServiceDay(tester);
    final now = DateTime(end.year, end.month, end.day, 8);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(_app(StopBoardSheet(stop: _hidroA, clock: () => now)));
    await _settle(tester);

    expect(find.textContaining('Timetable data ended'), findsNothing);
    expect(find.textContaining('No departures'), findsNothing);
    // Departure rows show both trip ends as "first → last".
    expect(find.textContaining(' → '), findsWidgets);
  });

  for (final locale in ['en', 'ro', 'de']) {
    testWidgets(
        '$locale: on the last service date neither Settings nor the '
        'Timetable tab says the data ended', (tester) async {
      final end = await _lastServiceDay(tester);
      final lastMinute = DateTime(end.year, end.month, end.day, 23, 59);
      final ended = (await _l10n(locale))
          .stopBoardFeedEnded(CompanionCatalog.isoDate(end));

      await tester.pumpWidget(_app(const SettingsTab(),
          locale: locale, overrides: [_pinClock(lastMinute)]));
      await _settle(tester);
      expect(find.text(ended), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pumpTimetable(tester, now: lastMinute, locale: locale);
      expect(find.text(ended), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.text((await _l10n(locale)).busTabUrban), findsOneWidget);
    });

    testWidgets(
        '$locale: the day after the last service date Settings shows the '
        'warning row with that date', (tester) async {
      final end = await _lastServiceDay(tester);
      await tester.pumpWidget(_app(const SettingsTab(),
          locale: locale,
          overrides: [
            _pinClock(DateTime(end.year, end.month, end.day + 1, 0, 1))
          ]));
      await _settle(tester);

      final l10n = await _l10n(locale);
      expect(find.text(l10n.stopBoardFeedEnded(CompanionCatalog.isoDate(end))),
          findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  }

  testWidgets(
      'the board without its own clock follows clockProvider: the day after '
      'the last service date it says the data ended', (tester) async {
    final end = await _lastServiceDay(tester);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const StopBoardSheet(stop: _hidroA),
        overrides: [_pinClock(DateTime(end.year, end.month, end.day + 1, 8))]));
    await _settle(tester);

    final l10n = await _l10n('en');
    expect(find.text(l10n.stopBoardFeedEnded(CompanionCatalog.isoDate(end))),
        findsOneWidget);
  });

  testWidgets(
      'de at 320x568: the Timetable tab fits the "data ended" notice without '
      'overflow', (tester) async {
    final end = await _lastServiceDay(tester);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpTimetable(tester,
        now: DateTime(end.year, end.month, end.day + 1, 8), locale: 'de');

    final l10n = await _l10n('de');
    expect(find.text(l10n.stopBoardFeedEnded(CompanionCatalog.isoDate(end))),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Settings: a pack whose services ended on 2026-01-31 shows the warning '
      'row on 1 Feb', (tester) async {
    await _seedPackEndingJan31(tester, docs);
    await tester.pumpWidget(_app(const SettingsTab(),
        overrides: [_pinClock(DateTime(2026, 2, 1, 8))]));
    await _settle(tester);
    final l10n = await _l10n('en');
    expect(find.text(l10n.stopBoardFeedEnded('2026-01-31')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets(
      'Settings: the same pack shows no warning row on its last day, 31 Jan',
      (tester) async {
    await _seedPackEndingJan31(tester, docs);
    await tester.pumpWidget(_app(const SettingsTab(),
        overrides: [_pinClock(DateTime(2026, 1, 31, 23, 59))]));
    await _settle(tester);
    expect(find.textContaining('Timetable data ended'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
