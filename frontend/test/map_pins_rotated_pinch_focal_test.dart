import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// Stop pins on a rotated map, and the damped pinch keeping the point between
// the fingers still, on the real bundled pack.

const _deniedForever = 1;
const _whileInUse = 2;
const _screen = Size(400, 800);

Future<void> _pumpMap(WidgetTester tester, {required bool located}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FakeGeolocator(grantOnRequest: false)
    ..permission = located ? _whileInUse : _deniedForever
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

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(TileLayer)));

Set<LatLng> _pins(WidgetTester tester) => {
      for (final layer
          in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)))
        for (final m in layer.markers)
          if (m.width == 32 || m.width == 40) m.point,
    };

/// Two fingers at [focal] ± [from]/2 horizontally, moved to ± [to]/2 in
/// small steps, then lifted.
Future<void> _pinch(WidgetTester tester, Offset focal,
    {required double from, required double to, int firstPointer = 1}) async {
  final a = await tester.startGesture(focal - Offset(from / 2, 0),
      pointer: firstPointer);
  final b = await tester.startGesture(focal + Offset(from / 2, 0),
      pointer: firstPointer + 1);
  const steps = 60;
  for (var i = 1; i <= steps; i++) {
    final half = (from + (to - from) * i / steps) / 2;
    await a.moveTo(focal - Offset(half, 0));
    await b.moveTo(focal + Offset(half, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await a.up();
  await b.up();
  await settleLocation(tester);
}

void main() {
  usePackTestEnv(prefix: 'rotransit_pins_rotated_');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => CompanionCatalog.instance.reset());

  testWidgets(
      'on a map rotated ~40 degrees at zoom 16, every stop drawn inside the '
      'screen, corners included, has a pin', (tester) async {
    await _pumpMap(tester, located: true);
    expect(_camera(tester).zoom, closeTo(16, 1e-6));

    // Twist 40 degrees at a constant 200 px spread (rotation threshold 18).
    final c = await tester.startGesture(const Offset(100, 400), pointer: 1);
    final d = await tester.startGesture(const Offset(300, 400), pointer: 2);
    for (var deg = 2; deg <= 40; deg += 2) {
      final r = deg * math.pi / 180;
      final off = Offset(100 * math.cos(r), 100 * math.sin(r));
      await c.moveTo(const Offset(200, 400) - off);
      await d.moveTo(const Offset(200, 400) + off);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await c.up();
    await d.up();
    await settleLocation(tester);

    final cam = _camera(tester);
    expect(cam.rotation.abs(), greaterThan(20));
    expect(cam.zoom, greaterThanOrEqualTo(kStopPinsMinZoom));
    final stops =
        await tester.runAsync(() => CompanionCatalog.instance.allStops());
    final onScreen = <LatLng>{
      for (final s in stops!)
        if ((Offset.zero & _screen)
            .contains(cam.latLngToScreenOffset(LatLng(s.lat, s.lon))))
          LatLng(s.lat, s.lon),
    };
    expect(onScreen, isNotEmpty);
    expect(onScreen.difference(_pins(tester)), isEmpty,
        reason: 'stops on screen without a pin');
  });

  testWidgets(
      'an off-centre pinch keeps the map point between the fingers under '
      'them, zooming in and out', (tester) async {
    await _pumpMap(tester, located: true); // zoom 16, pins on
    const focal = Offset(170, 300); // left of centre; fingers stay on screen

    final anchor = _camera(tester).screenOffsetToLatLng(focal);
    final z0 = _camera(tester).zoom;
    await _pinch(tester, focal, from: 100, to: 300);
    var cam = _camera(tester);
    // Zoom starts once the pinch wins at ~1.57x (threshold 0.65), here at a
    // ~158 px spread, so damped: 0.7 * log2(300 / ~158) = ~0.64. Undamped
    // flutter_map lands at ~1.28, and an undamped log2 at ~0.93.
    expect(cam.zoom - z0, inInclusiveRange(0.55, 0.75));
    expect((cam.latLngToScreenOffset(anchor) - focal).distance,
        lessThan(3), reason: 'point under the fingers drifted');

    final anchor2 = cam.screenOffsetToLatLng(focal);
    final z1 = cam.zoom;
    await _pinch(tester, focal, from: 300, to: 100, firstPointer: 3);
    cam = _camera(tester);
    // Mirror image: the pinch wins at a ~191 px spread, so damped:
    // 0.7 * log2(100 / ~191) = ~-0.65 (undamped log2: ~-0.93).
    expect(cam.zoom - z1, inInclusiveRange(-0.75, -0.55));
    expect((cam.latLngToScreenOffset(anchor2) - focal).distance,
        lessThan(3), reason: 'point under the fingers drifted');
  });
}
