import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/favorites/data/favorite_stops_repository.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/favorites_tab.dart';
import 'package:rotransit/src/features/shell/state/bus_line_open_provider.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FavoritesTab(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows "Could not load favorites" for each failed section',
      (tester) async {
    final c = ProviderContainer(overrides: [
      favoriteStopsProvider.overrideWith((ref) async => throw StateError('x')),
      favoriteLinesProvider.overrideWith((ref) async => throw StateError('y')),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    expect(find.text('Could not load favorites'), findsNWidgets(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a failing stops section does not hide favorite lines',
      (tester) async {
    final c = ProviderContainer(overrides: [
      favoriteStopsProvider.overrideWith((ref) async => throw StateError('x')),
    ]);
    addTearDown(c.dispose);
    await FavoriteStopsRepository().toggleLine(const BusLine(
        routeId: 'rt-36', shortName: '36', longName: 'Gara', mode: 'bus'));
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    expect(find.text('Could not load favorites'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
  });

  testWidgets(
      'empty state, then saved stop and line appear after a revision '
      'bump, and tapping the line opens it in Timetable', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.textContaining('No favorite stops yet'), findsOneWidget);
    expect(find.textContaining('No favorite lines yet'), findsOneWidget);

    final repo = FavoriteStopsRepository();
    await tester.runAsync(() async {
      await repo.toggleStop(const StopSearchItem(
          stopId: 'node/1', name: 'Livada Poștei', lat: 45.6, lon: 25.5));
      await repo.toggleLine(const BusLine(
          routeId: 'rt-5', shortName: '5', longName: 'Roman', mode: 'bus'));
    });
    c.read(favoriteStopsRevisionProvider.notifier).state++;
    c.read(favoriteLinesRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text('Livada Poștei'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(c.read(selectedTabProvider), 1);
    expect(c.read(pendingOpenBusLineProvider)?.line.routeId, 'rt-5');
  });
}
