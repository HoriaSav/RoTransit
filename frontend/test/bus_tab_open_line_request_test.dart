import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/bundled_pack_bootstrap.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/bus_tab.dart';
import 'package:rotransit/src/features/shell/state/bus_line_open_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

// Real pack data: line 36, direction 1, stop 11 is Ștefan Baciu
// (node/11671674450). That stop is not on direction 0 at all.
const _line36 = BusLine(
  routeId: '36',
  shortName: '36',
  longName: 'Independenței - Livada Poștei',
  mode: 'BUS',
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  usePackTestEnv(prefix: 'rotransit_bus_open_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpBusTab(WidgetTester tester) async {
    final c = ProviderContainer();
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
          home: const BusTab(),
        ),
      ),
    );
    await _settle(tester);
    return c;
  }

  testWidgets(
      'a stop-board request opens line 36 on direction 1 with the '
      'chosen stop selected', (tester) async {
    final c = await pumpBusTab(tester);

    c.read(pendingOpenBusLineProvider.notifier).state =
        const OpenBusLineRequest(
      line: _line36,
      stopId: 'node/11671674450',
      directionId: '1',
    );
    await _settle(tester);

    expect(find.text('11. Ștefan Baciu'), findsOneWidget);
    expect(c.read(pendingOpenBusLineProvider), isNull,
        reason: 'request is consumed once');
  });

  testWidgets(
      'control: without a stop and direction the line opens on '
      'direction 0 at its first stop', (tester) async {
    final c = await pumpBusTab(tester);

    c.read(pendingOpenBusLineProvider.notifier).state =
        const OpenBusLineRequest(line: _line36);
    await _settle(tester);

    expect(find.text('1. Independenței'), findsOneWidget);
    expect(find.text('11. Ștefan Baciu'), findsNothing);
  });
}
