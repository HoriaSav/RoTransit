import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_companion_tab.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';

StopSearchItem _stop(String id, String name) =>
    StopSearchItem(stopId: id, name: name, lat: 45.6, lon: 25.5);

/// Records every searchStops call; answers from [answer].
class _FakeCatalog implements CompanionCatalog {
  _FakeCatalog(this.answer);
  final Future<List<StopSearchItem>> Function(String q) answer;
  final queries = <String>[];

  @override
  Future<List<StopSearchItem>> searchStops(String query, {int limit = 20}) {
    queries.add(query);
    return answer(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(WidgetTester tester, _FakeCatalog fake) async {
  final c = ProviderContainer(
    overrides: [companionCatalogProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MapCompanionTab()),
      ),
    ),
  );
  await tester.pump();
  return c;
}

Finder get _field => find.byType(TextField);
Finder get _spinner => find.byType(CircularProgressIndicator);

void main() {
  testWidgets('fast typing runs one search, for the last text, after 150 ms',
      (tester) async {
    final fake = _FakeCatalog((q) async => [_stop('a', 'Livada Poștei')]);
    await _pump(tester, fake);

    for (final t in ['Li', 'Liv', 'Liva', 'Livad']) {
      await tester.enterText(_field, t);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fake.queries, isEmpty, reason: 'still inside the debounce window');

    await tester.pump(const Duration(milliseconds: 60));
    expect(fake.queries, ['Livad']);
    await tester.pumpAndSettle();
    expect(find.text('Livada Poștei'), findsOneWidget);
    expect(fake.queries, hasLength(1));
  });

  testWidgets('one-letter text does not search and clears suggestions',
      (tester) async {
    final fake = _FakeCatalog((q) async => [_stop('a', 'Livada Poștei')]);
    await _pump(tester, fake);

    await tester.enterText(_field, 'Li');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Livada Poștei'), findsOneWidget);

    await tester.enterText(_field, 'L');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(fake.queries, ['Li']);
    expect(find.text('Livada Poștei'), findsNothing);
  });

  testWidgets('a slow older search cannot overwrite a newer one',
      (tester) async {
    final pending = <String, Completer<List<StopSearchItem>>>{};
    final fake = _FakeCatalog((q) => (pending[q] = Completer()).future);
    await _pump(tester, fake);

    await tester.enterText(_field, 'Li');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.enterText(_field, 'Gara');
    await tester.pump(const Duration(milliseconds: 160));
    expect(fake.queries, ['Li', 'Gara']);

    pending['Gara']!.complete([_stop('g', 'Gara Brașov')]);
    await tester.pump();
    pending['Li']!.complete([_stop('a', 'Livada Poștei')]);
    await tester.pump();

    expect(find.text('Gara Brașov'), findsOneWidget);
    expect(find.text('Livada Poștei'), findsNothing);
    expect(_spinner, findsNothing);
  });

  testWidgets('a failing search stops the spinner and shows no suggestions',
      (tester) async {
    final fake = _FakeCatalog((q) async => throw StateError('pack missing'));
    await _pump(tester, fake);

    await tester.enterText(_field, 'Livada');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump();
    expect(fake.queries, ['Livada']);
    expect(_spinner, findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'choosing a stop focuses it exactly once, even with a search '
      'still waiting in the debounce', (tester) async {
    final livada = _stop('node/1', 'Livada Poștei');
    final fake = _FakeCatalog((q) async => [livada]);
    final c = await _pump(tester, fake);
    final focused = <StopSearchItem?>[];
    c.listen(companionFocusStopProvider, (_, next) => focused.add(next));

    await tester.enterText(_field, 'Liv');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    // User types one more letter, then taps before the debounce fires.
    await tester.enterText(_field, 'Liva');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Livada Poștei'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(focused, [livada]);
    expect(fake.queries, ['Liv'], reason: 'pending search must be cancelled');
    expect(find.byType(ListTile), findsNothing);
    expect(tester.widget<TextField>(_field).controller!.text, 'Livada Poștei');
  });
}
