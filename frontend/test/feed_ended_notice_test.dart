import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/settings/presentation/settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/pack_test_env.dart';

// "Timetable data ended" on the stop board and in Settings, against the real
// bundled pack. The last service date comes from the pack itself, so these
// tests keep working when the pack is refreshed.
const _hidroA = StopSearchItem(
    stopId: 'node/8227802075', name: 'Hidro A', lat: 45.6, lon: 25.6);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home, {String locale = 'en'}) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );

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

  testWidgets('Settings: no "data ended" row while the pack is still current',
      (tester) async {
    await tester.runAsync(() => CompanionCatalog.instance.meta());
    await tester.pumpWidget(_app(const SettingsTab()));
    await _settle(tester);
    expect(find.text('Brașov data as of'), findsOneWidget);
    expect(find.textContaining('Timetable data ended'), findsNothing);
  });

  testWidgets(
      'Settings: a pack whose services have all ended shows the warning row '
      'with the last service date', (tester) async {
    // Extract the real pack, then end every service on 2026-01-31, well
    // before today, the way an old install would look after May 2027.
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

    await tester.pumpWidget(_app(const SettingsTab()));
    await _settle(tester);
    final l10n = await _l10n('en');
    expect(find.text(l10n.stopBoardFeedEnded('2026-01-31')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
