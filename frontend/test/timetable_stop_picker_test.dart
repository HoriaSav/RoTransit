import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/timetable_stop_picker.dart';

void main() {
  testWidgets('stop picker has top back and pops selected stop id',
      (tester) async {
    String? result;
    final stops = [
      const RouteStop(
        stopId: 'A',
        name: 'Alpha',
        lat: 1,
        lon: 2,
        stopSequence: 1,
      ),
      const RouteStop(
        stopId: 'B',
        name: 'Beta',
        lat: 3,
        lon: 4,
        stopSequence: 2,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => TimetableStopPickerPage(
                      stops: stops,
                      selectedStopId: 'A',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Select stop'), findsOneWidget);
    expect(find.text('1. Alpha'), findsOneWidget);
    expect(find.text('2. Beta'), findsOneWidget);

    await tester.tap(find.text('2. Beta'));
    await tester.pumpAndSettle();
    expect(result, 'B');
  });

  testWidgets('stop picker back dismisses without selection', (tester) async {
    var completed = false;
    String? result = 'sentinel';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const TimetableStopPickerPage(
                      stops: [
                        RouteStop(
                          stopId: 'A',
                          name: 'Alpha',
                          lat: 1,
                          lon: 2,
                          stopSequence: 1,
                        ),
                      ],
                    ),
                  ),
                );
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
  });
}
