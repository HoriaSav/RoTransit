import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:rotransit/src/features/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// Launch location when the first GPS fix is slow: it must not move a map the
// rider already panned, and it must not start GPS while another tab is shown.

const _fix = LatLng(45.6427, 25.5887); // FakeGeolocator's getCurrentPosition
const _whileInUse = 2; // LocationPermission index on the wire

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(TileLayer)));

void main() {
  usePackTestEnv(prefix: 'rotransit_launch_slow_fix_');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'RoTransit',
      packageName: 'ro.rotransit',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => CompanionCatalog.instance.reset());

  testWidgets(
      'a slow launch fix after the rider panned shows the dot and starts the '
      'stream but leaves the camera where the rider put it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _whileInUse
      ..holdPosition = Completer<void>()
      ..install(tester);
    await tester.runAsync(() => CompanionCatalog.instance.allStops());
    await tester.pumpWidget(_app(const Scaffold(body: MapTab())));
    await settleLocation(tester);
    expect(geo.calls, contains('getCurrentPosition'),
        reason: 'launch is waiting on the first fix');
    expect(userDot(tester), isNull);

    // One-finger pan while the fix is pending, resting before lifting so
    // there is no fling.
    final g = await tester.startGesture(const Offset(200, 400));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(200 - 12.0 * i, 400));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await settleLocation(tester);
    final panned = _camera(tester);
    expect(panned.zoom, closeTo(kStopPinsMinZoom, 1e-6));

    geo.holdPosition!.complete();
    await settleLocation(tester);

    expect(userDot(tester), _fix);
    expect(geo.sink, isNotNull, reason: 'live stream starts after the fix');
    final cam = _camera(tester);
    expect(cam.center.latitude, closeTo(panned.center.latitude, 1e-9));
    expect(cam.center.longitude, closeTo(panned.center.longitude, 1e-9));
    expect(cam.zoom, closeTo(kStopPinsMinZoom, 1e-9), reason: 'no jump to zoom 16');
  });

  testWidgets(
      'a slow launch fix that lands while the Timetable tab is shown does '
      'not start GPS until the map is visible again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _whileInUse
      ..holdPosition = Completer<void>()
      ..install(tester);
    await tester.pumpWidget(_app(const MainShell()));
    await settleLocation(tester);
    expect(geo.calls, contains('getCurrentPosition'));

    await tester.tap(find.text('Timetable').last);
    await settleLocation(tester);
    geo.holdPosition!.complete();
    await settleLocation(tester);
    expect(geo.listenArgs, isEmpty, reason: 'no GPS stream off the map');

    await tester.tap(find.text('Map').last);
    await settleLocation(tester);
    expect(geo.sink, isNotNull, reason: 'stream starts once the map shows');
    expect((geo.listenArgs.single as Map)['distanceFilter'], 15);
    expect(userDot(tester), _fix);
  });
}
