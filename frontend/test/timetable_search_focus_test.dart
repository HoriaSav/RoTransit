import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/bus_tab.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('returning from line board leaves search unfocused',
      (tester) async {
    const line = BusLine(
      routeId: 'R1',
      shortName: '5',
      longName: 'Test Line',
      mode: 'BUS',
    );
    const stops = [
      RouteStop(
        stopId: 'S1',
        name: 'Stop One',
        lat: 45.6,
        lon: 25.6,
        stopSequence: 1,
      ),
      RouteStop(
        stopId: 'S2',
        name: 'Stop Two',
        lat: 45.61,
        lon: 25.61,
        stopSequence: 2,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cityOfflinePackInstalledProvider.overrideWith((ref) async => true),
          busesProvider.overrideWith((ref) async => [line]),
          routeStopsProvider.overrideWith((ref, args) async => stops),
          routeTimetableProvider.overrideWith(
            (ref, args) async => const StopTimetable(
              cityId: 'c',
              routeId: 'R1',
              stopId: 'S1',
              serviceDate: '2026-01-19',
              departures: [],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BusTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Focus the search field.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final focusBefore = tester.widget<TextField>(find.byType(TextField));
    expect(focusBefore.focusNode?.hasFocus, isTrue);

    // Open line board (tile tap — avoid favorite heart).
    await tester.tap(find.text('Test Line'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsWidgets);

    // Pop back.
    await tester.tap(find.byTooltip('Back').first);
    await tester.pumpAndSettle();

    final focusAfter = tester.widget<TextField>(find.byType(TextField));
    expect(focusAfter.focusNode?.hasFocus, isFalse);
    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(focusAfter.focusNode)),
    );
  });

  testWidgets('line list shows favorite-line heart', (tester) async {
    const line = BusLine(
      routeId: 'R1',
      shortName: '5',
      longName: 'Heart Line',
      mode: 'BUS',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cityOfflinePackInstalledProvider.overrideWith((ref) async => true),
          busesProvider.overrideWith((ref) async => [line]),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BusTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Favorite line'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });
}
