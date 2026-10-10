import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/bus_tab.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _line = BusLine(
    routeId: 'R1', shortName: '5', longName: 'Busy Line', mode: 'BUS');
const _stops = [
  RouteStop(
      stopId: 'S1', name: 'Stop One', lat: 45.6, lon: 25.6, stopSequence: 1),
  RouteStop(
      stopId: 'S2', name: 'Stop Two', lat: 45.61, lon: 25.61, stopSequence: 2),
];

/// A dense timetable: a departure every 4 minutes, 05:00–23:56.
StopTimetable _busy() => StopTimetable(
      cityId: 'c',
      routeId: 'R1',
      stopId: 'S1',
      serviceDate: '2026-10-01',
      departures: [
        for (var h = 5; h < 24; h++)
          for (var m = 0; m < 60; m += 4)
            StopTimetableEntry(
              tripId: 't$h$m',
              headsign: 'Stop Two',
              departureTime:
                  '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00',
            ),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('week timetable fits a 320x568 screen with pinch-to-zoom',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cityOfflinePackInstalledProvider.overrideWith((ref) async => true),
          busesProvider.overrideWith((ref) async => [_line]),
          routeStopsProvider.overrideWith((ref, args) async => _stops),
          routeTimetableProvider.overrideWith((ref, args) async => _busy()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BusTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Busy Line'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow errors');
    final zoom = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('week-timetable-zoom')));
    expect(zoom.maxScale, inInclusiveRange(2.0, 2.5));
    expect(zoom.minScale, 1);
    // All three day columns are on screen at the default size.
    for (final label in ['Mon-Fri', 'Sat', 'Sun']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(320), reason: label);
    }
    // Readable default size (no shrink-to-fit).
    final minutes = tester.widget<Text>(find.textContaining('00  04').first);
    expect(minutes.style?.fontSize, greaterThanOrEqualTo(14));
  });
}
