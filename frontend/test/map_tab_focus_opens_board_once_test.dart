import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_companion_tab.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  usePackTestEnv(prefix: 'rotransit_map_focus_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'a search selection opens the stop board exactly once, and the '
      'same stop can be opened again later', (tester) async {
    final stop = (await tester.runAsync(() async {
      final all = await CompanionCatalog.instance.allStops();
      return all.firstWhere((s) => s.stopId == 'node/11016370557');
    }))!;

    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: MapTab()),
        ),
      ),
    );
    await _settle(tester);

    c.read(companionFocusStopProvider.notifier).state = stop;
    await _settle(tester);

    expect(find.byType(StopBoardSheet), findsOneWidget);
    expect(c.read(companionFocusStopProvider), isNull,
        reason: 'MapTab clears the request after handling it');

    // Close the sheet, then choose the same stop again.
    Navigator.of(tester.element(find.byType(StopBoardSheet))).pop();
    await _settle(tester);
    expect(find.byType(StopBoardSheet), findsNothing);

    c.read(companionFocusStopProvider.notifier).state = StopSearchItem(
        stopId: stop.stopId, name: stop.name, lat: stop.lat, lon: stop.lon);
    await _settle(tester);
    expect(find.byType(StopBoardSheet), findsOneWidget);
  });
}
