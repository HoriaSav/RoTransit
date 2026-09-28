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
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// Stop pins by zoom and viewport, and the damped pinch zoom, on the real
// bundled pack. Launch location puts the camera at zoom 16 over the old town
// (permission granted) or leaves it at the default zoom 11 (denied).

const _deniedForever = 1;
const _whileInUse = 2;

Future<void> _pumpMap(WidgetTester tester, {required bool located}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FakeGeolocator(grantOnRequest: false)
    ..permission = located ? _whileInUse : _deniedForever
    ..install(tester);
  // Open the pack outside fake time; MapTab then gets the cached stops.
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

/// Points of the rendered stop pins (32 px, 40 px when selected).
Set<LatLng> _pins(WidgetTester tester) => {
      for (final layer
          in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)))
        for (final m in layer.markers)
          if (m.width == 32 || m.width == 40) m.point,
    };

Future<List<LatLng>> _allStops(WidgetTester tester) async {
  final stops =
      await tester.runAsync(() => CompanionCatalog.instance.allStops());
  return [for (final s in stops!) LatLng(s.lat, s.lon)];
}

/// [b] grown by [f] of its size on each side.
LatLngBounds _grow(LatLngBounds b, double f) {
  final dLat = (b.north - b.south) * f;
  final dLon = (b.east - b.west) * f;
  return LatLngBounds(LatLng(b.south - dLat, b.west - dLon),
      LatLng(b.north + dLat, b.east + dLon));
}

/// One finger drag without a fling (it rests before lifting).
Future<void> _slowDrag(WidgetTester tester, Offset by) async {
  final g = await tester.startGesture(const Offset(200, 400));
  for (var i = 1; i <= 20; i++) {
    await g.moveTo(const Offset(200, 400) + by * (i / 20));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await g.up();
  await settleLocation(tester);
}

void main() {
  usePackTestEnv(prefix: 'rotransit_stop_pins_');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => CompanionCatalog.instance.reset());

  test('pin area is the visible bounds plus a quarter on each side', () {
    final b = stopPinBounds(
        LatLngBounds(const LatLng(45.60, 25.50), const LatLng(45.64, 25.58)));
    expect(b.south, closeTo(45.59, 1e-9));
    expect(b.north, closeTo(45.65, 1e-9));
    expect(b.west, closeTo(25.48, 1e-9));
    expect(b.east, closeTo(25.60, 1e-9));
  });

  testWidgets('below zoom 15 no stop pins are drawn and map taps open nothing',
      (tester) async {
    await _pumpMap(tester, located: false);
    expect(_camera(tester).zoom, lessThan(kStopPinsMinZoom));
    expect(await _allStops(tester), isNotEmpty);

    expect(_pins(tester), isEmpty);
    expect(find.byIcon(Icons.directions_bus_rounded), findsNothing);

    // The default view is Brașov's centre, with stops around it.
    await tester.tapAt(const Offset(200, 400));
    await settleLocation(tester);
    expect(find.byType(StopBoardSheet), findsNothing);
  });

  testWidgets(
      'at zoom 16 only stops around the view get pins, and every stop in '
      'view has one', (tester) async {
    await _pumpMap(tester, located: true);
    final cam = _camera(tester);
    expect(cam.zoom, closeTo(16, 1e-6));
    final all = await _allStops(tester);
    final pins = _pins(tester);

    final inView = all.where(cam.visibleBounds.contains).toSet();
    expect(inView, isNotEmpty);
    expect(pins.containsAll(inView), isTrue,
        reason: 'no stop in view left out');
    // The 25% margin, plus the area kept from the zoom-in past 15.
    final near = _grow(cam.visibleBounds, 1.5);
    expect(pins.where((p) => !near.contains(p)), isEmpty);
    expect(pins.length, lessThan(all.length ~/ 4));
  });

  testWidgets('panning past the margin updates the pins to the new view',
      (tester) async {
    await _pumpMap(tester, located: true);
    final all = await _allStops(tester);
    final before = _pins(tester);

    // A full screen width left: well past the 25% margin.
    await _slowDrag(tester, const Offset(-400, 0));
    final cam = _camera(tester);
    final after = _pins(tester);

    expect(after, isNot(before));
    final inView = all.where(cam.visibleBounds.contains).toSet();
    expect(inView, isNotEmpty);
    expect(after.containsAll(inView), isTrue);
    final near = _grow(cam.visibleBounds, 1.5);
    expect(after.where((p) => !near.contains(p)), isEmpty);
  });

  testWidgets('tapping a visible stop pin opens its board', (tester) async {
    await _pumpMap(tester, located: true);
    final visible = find.byIcon(Icons.directions_bus_rounded).evaluate().where(
      (e) {
        final c = tester.getCenter(find.byWidget(e.widget));
        return c.dx > 40 && c.dx < 360 && c.dy > 80 && c.dy < 720;
      },
    );
    expect(visible, isNotEmpty);

    await tester.tap(find.byWidget(visible.first.widget));
    await settleLocation(tester);
    expect(find.byType(StopBoardSheet), findsOneWidget);
  });

  testWidgets(
      'pinch zoom is damped: doubling the finger spread zooms in by well '
      'under the undamped amount; a twist rotates without zooming',
      (tester) async {
    await _pumpMap(tester, located: false);
    final startZoom = _camera(tester).zoom;

    // Spread 200 px -> 400 px around the centre in 4 px steps.
    final a = await tester.startGesture(const Offset(100, 400), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 400), pointer: 2);
    for (var d = 2; d <= 100; d += 2) {
      await a.moveTo(Offset(100.0 - d, 400));
      await b.moveTo(Offset(300.0 + d, 400));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await settleLocation(tester);
    final zoomed = _camera(tester).zoom - startZoom;
    // Zoom starts once the pinch wins at ~log2(1.57) (spread ~314 px).
    // Undamped flutter_map lands at ~0.5; damped: 0.7 * log2(400 / ~318).
    expect(zoomed, greaterThan(0.15));
    expect(zoomed, lessThan(0.32));

    // Twist 40 degrees at a constant 200 px spread.
    final zoomBefore = _camera(tester).zoom;
    final c = await tester.startGesture(const Offset(100, 400), pointer: 3);
    final d = await tester.startGesture(const Offset(300, 400), pointer: 4);
    for (var deg = 2; deg <= 40; deg += 2) {
      final r = deg * math.pi / 180;
      final off = Offset(100 * math.cos(r), 100 * math.sin(r));
      await c.moveTo(const Offset(200, 400) - off);
      await d.moveTo(const Offset(200, 400) + off);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await c.up();
    await d.up();
    await settleLocation(tester);
    expect(_camera(tester).rotation.abs(), greaterThan(10));
    expect(_camera(tester).zoom, closeTo(zoomBefore, 1e-6));
  });
}
