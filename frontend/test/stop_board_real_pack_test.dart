import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

// Stop board against the real bundled pack.
// The four busiest Mon–Fri stops in the pack (Hidro A, Sanitas, Liceul
// Meșotă, and node/2552635273) have many departures in the same minute, so
// they show whether the order of equal-minute rows stays put when the window
// grows.
const _busyStops = [
  'node/8227802075',
  'node/2537929578',
  'node/267042578',
  'node/2552635273',
];

String _key(StopBoardDeparture d) => '${d.departureTime}|${d.tripId}';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  required StopSearchItem stop,
  required DateTime now,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StopBoardSheet(stop: stop, clock: () => now)),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePackTestEnv(prefix: 'rotransit_board_real_');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final catalog = CompanionCatalog.instance;

  for (final from in [
    DateTime(2026, 10, 14, 7, 30), // Wednesday rush hour
    DateTime(2026, 10, 16, 23, 40), // Friday, window crosses midnight
  ]) {
    test(
        '+30 min only appends: each longer window starts with exactly the '
        'rows of the shorter one, in the same order ($from)', () async {
      for (final stopId in _busyStops) {
        var previous = <String>[];
        for (var window = 30; window <= 180; window += 30) {
          final keys = [
            for (final d in await catalog.stopBoard(
                stopId: stopId, from: from, windowMinutes: window))
              _key(d),
          ];
          expect(keys.take(previous.length).toList(), previous,
              reason: '$stopId: rows reordered when the window went to '
                  '$window min');
          previous = keys;
        }
        expect(previous, isNotEmpty, reason: '$stopId has no departures');
      }
    });
  }

  test('every row on a busy board carries both trip ends', () async {
    for (final stopId in _busyStops) {
      final board = await catalog.stopBoard(
          stopId: stopId,
          from: DateTime(2026, 10, 14, 5, 0),
          windowMinutes: 23 * 60);
      expect(board, isNotEmpty);
      for (final d in board) {
        expect(d.firstStopName.trim(), isNotEmpty, reason: d.tripId);
        expect(d.lastStopName.trim(), isNotEmpty, reason: d.tripId);
      }
    }
  });

  testWidgets(
      'line 36 at Ștefan Baciu reads "Livada Poștei → Independenței", '
      'the direction it actually runs', (tester) async {
    await _pumpBoard(
      tester,
      stop: const StopSearchItem(
          stopId: 'node/11671674450',
          name: 'Ștefan Baciu',
          lat: 45.6,
          lon: 25.6),
      now: DateTime(2026, 10, 14, 8, 0),
    );
    final row36 = find.ancestor(
      of: find.text('36'),
      matching: find.byType(InkWell),
    );
    expect(row36, findsWidgets);
    expect(
      find.descendant(
          of: row36.first,
          matching: find.text('Livada Poștei → Independenței')),
      findsOneWidget,
    );
  });

  for (final (locale, window) in [
    ('en', 'Next'),
    ('ro', 'Următoarele'),
    ('de', 'Nächste'),
  ]) {
    testWidgets(
        '$locale: board header is localized and never says '
        '"Scheduled"', (tester) async {
      await _pumpBoard(
        tester,
        stop: const StopSearchItem(
            stopId: 'node/8227802075', name: 'Hidro A', lat: 45.6, lon: 25.6),
        now: DateTime(2026, 10, 14, 8, 0),
        locale: locale,
      );
      expect(find.textContaining(window), findsWidgets);
      for (final w in [
        'Scheduled',
        'scheduled',
        'Programat',
        'programat',
        'Planmäßig',
        'planmäßig',
        'Geplant',
        'geplant'
      ]) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
    });
  }
}
