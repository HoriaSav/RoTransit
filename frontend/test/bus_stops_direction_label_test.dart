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

// Line 36: direction 0 ends at Livada Poștei, direction 1 at Independenței.
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
  usePackTestEnv(prefix: 'rotransit_direction_label_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openLine(WidgetTester tester, String directionId) async {
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
    c.read(pendingOpenBusLineProvider.notifier).state =
        OpenBusLineRequest(line: _line36, directionId: directionId);
    await _settle(tester);
  }

  testWidgets('direction 1 reads "Towards: <its last stop>"', (tester) async {
    await openLine(tester, '1');
    expect(find.text('Towards: Independenței'), findsOneWidget);
    expect(find.textContaining('From:'), findsNothing);
  });

  testWidgets('direction 0 reads "Towards: <its last stop>"', (tester) async {
    await openLine(tester, '0');
    expect(find.text('Towards: Livada Poștei'), findsOneWidget);
  });
}
