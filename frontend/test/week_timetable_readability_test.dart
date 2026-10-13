import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';
import 'package:rotransit/src/features/saved/presentation/bus_tab.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Layout checks with the real Roboto font (the default test font draws every
// glyph 1em wide, which makes width checks meaningless). Roboto comes from the
// Flutter SDK cache; the width tests skip if it cannot be found.

const _line =
    BusLine(routeId: 'R1', shortName: '5', longName: 'Busy Line', mode: 'BUS');
const _stops = [
  RouteStop(
      stopId: 'S1', name: 'Stop One', lat: 45.6, lon: 25.6, stopSequence: 1),
  RouteStop(
      stopId: 'S2', name: 'Stop Two', lat: 45.61, lon: 25.61, stopSequence: 2),
];

/// Every 4 minutes, 05:00–23:56, so hour rows wrap onto several lines.
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
              departureTime: '${h.toString().padLeft(2, '0')}:'
                  '${m.toString().padLeft(2, '0')}:00',
            ),
      ],
    );

Directory? _materialFonts() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory('${dir.path}/artifacts/material_fonts');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final d = Directory('$root/bin/cache/artifacts/material_fonts');
    if (d.existsSync()) return d;
  }
  return null;
}

Future<bool> _loadRoboto() async {
  final dir = _materialFonts();
  if (dir == null) return false;
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    final f = File('${dir.path}/Roboto-$w.ttf');
    if (!f.existsSync()) return false;
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  return true;
}

Future<void> _pumpTimetable(
  WidgetTester tester, {
  required Size size,
  String locale = 'en',
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
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
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const BusTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Busy Line'));
  await tester.pumpAndSettle();
}

/// Number of laid-out lines of the paragraph that renders [text].
int _lines(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(find.text(text).first);
  final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length));
  return boxes.map((b) => b.top.round()).toSet().length;
}

const _headers = {
  'en': ['Hour', 'Mon-Fri', 'Sat', 'Sun'],
  'ro': ['Oră', 'L-V', 'Sâm', 'Dum'],
  'de': ['Stunde', 'Mo-Fr', 'Sa', 'So'],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  var roboto = false;
  setUpAll(() async => roboto = await _loadRoboto());

  for (final entry in _headers.entries) {
    testWidgets(
        '${entry.key}: at 360 px every header and hour label sits on one '
        'line (no letters broken off)', (tester) async {
      if (!roboto) {
        markTestSkipped('Roboto not found in the Flutter SDK cache');
        return;
      }
      await _pumpTimetable(tester,
          size: const Size(360, 740), locale: entry.key);
      expect(tester.takeException(), isNull);
      for (final label in entry.value) {
        expect(_lines(tester, label), 1, reason: '"$label" wraps');
      }
      expect(_lines(tester, '05'), 1, reason: 'hour "05" wraps');
    });
  }

  testWidgets('320 px screen at 130% text size: no overflow in any locale',
      (tester) async {
    for (final locale in _headers.keys) {
      await _pumpTimetable(tester,
          size: const Size(320, 568), locale: locale, textScale: 1.3);
      expect(tester.takeException(), isNull, reason: locale);
    }
  });

  testWidgets('pinch zooms in up to 2.5x and not beyond; back out stops at 1x',
      (tester) async {
    await _pumpTimetable(tester, size: const Size(360, 740));
    final base = tester.getRect(find.text('Sun')).height;
    final center =
        tester.getCenter(find.byKey(const ValueKey('week-timetable-zoom')));

    Future<void> pinch(double from, double to) async {
      final a = await tester.startGesture(center - Offset(from, 0));
      final b = await tester.startGesture(center + Offset(from, 0));
      for (var i = 1; i <= 10; i++) {
        final d = from + (to - from) * i / 10;
        await a.moveTo(center - Offset(d, 0));
        await b.moveTo(center + Offset(d, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    double scale() => tester.getRect(find.text('Sun')).height / base;

    await pinch(20, 40); // about 2x
    expect(scale(), greaterThan(1.5));
    expect(scale(), lessThanOrEqualTo(2.5 + 1e-6));

    await pinch(20, 150); // far past the limit
    expect(scale(), closeTo(2.5, 0.01));

    await pinch(150, 10); // far below 1x
    expect(scale(), closeTo(1.0, 0.01));
  });

  testWidgets('one-finger drag reaches the last hour row (23) at 1x',
      (tester) async {
    await _pumpTimetable(tester, size: const Size(360, 640));
    final viewport =
        tester.getRect(find.byKey(const ValueKey('week-timetable-zoom')));
    expect(tester.getRect(find.text('23')).top, greaterThan(viewport.bottom),
        reason: 'fixture must be taller than the screen');
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byKey(const ValueKey('week-timetable-zoom')),
          const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    final last = tester.getRect(find.text('23'));
    expect(last.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
    expect(last.top, greaterThanOrEqualTo(viewport.top - 0.5));
  });
}
