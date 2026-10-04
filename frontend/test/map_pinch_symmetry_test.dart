import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// Pinch zoom follows the fingers equally both ways, measured by finger
// spread: spreading x3 zooms in as much as pinching to a third zooms out.

const _deniedForever = 1;

Future<void> _pumpMap(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FakeGeolocator(grantOnRequest: false)
    ..permission = _deniedForever
    ..install(tester);
  await tester.runAsync(() => CompanionCatalog.instance.allStops());
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MapTab()),
      ),
    ),
  );
  await settleLocation(tester);
}

double _zoom(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(TileLayer))).zoom;

var _nextPointer = 1;

/// Vertical two-finger pinch around the screen centre from a [from] px to a
/// [to] px spread in 1 px steps per finger; returns the zoom change.
Future<double> _pinch(WidgetTester tester, double from, double to) async {
  final before = _zoom(tester);
  const c = Offset(200, 400);
  final a = await tester.startGesture(c - Offset(0, from / 2),
      pointer: _nextPointer++);
  final b = await tester.startGesture(c + Offset(0, from / 2),
      pointer: _nextPointer++);
  final steps = ((to - from).abs() / 2).round();
  for (var i = 1; i <= steps; i++) {
    final half = (from + (to - from) * i / steps) / 2;
    await a.moveTo(c - Offset(0, half));
    await b.moveTo(c + Offset(0, half));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await settleLocation(tester);
  return _zoom(tester) - before;
}

void main() {
  usePackTestEnv(prefix: 'rotransit_pinch_symmetry_');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => CompanionCatalog.instance.reset());

  for (final (small, large) in [(150.0, 450.0), (200.0, 400.0)]) {
    final ratio = (large / small).round();
    testWidgets(
        'spreading x$ratio zooms in as much as pinching to 1/$ratio zooms '
        'out', (tester) async {
      await _pumpMap(tester);
      final zoomIn = await _pinch(tester, small, large);
      final zoomOut = await _pinch(tester, large, small);

      expect(zoomIn, greaterThan(0.1));
      expect(zoomOut, lessThan(-0.1));
      expect(zoomIn.abs(), closeTo(zoomOut.abs(), 0.05),
          reason: 'in $zoomIn vs out $zoomOut');
    });
  }
}
