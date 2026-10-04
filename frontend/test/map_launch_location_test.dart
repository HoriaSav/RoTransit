import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/map/presentation/map_companion_tab.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:rotransit/src/features/map/presentation/stop_board_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// Launch location against the real location code and a fake Geolocator
// channel: permission states, one-time prompt, centering and the stream.

const _fix = LatLng(45.6427, 25.5887); // FakeGeolocator's getCurrentPosition
const _default = LatLng(45.6457, 25.5884); // Livada Poștei, zoom 15

// LocationPermission indexes on the wire.
const _deniedForever = 1;
const _whileInUse = 2;

Future<void> _pumpMap(WidgetTester tester,
    {ProviderContainer? container}) async {
  final c = container ?? ProviderContainer();
  if (container == null) addTearDown(c.dispose);
  // Open the pack outside fake time so no pack I/O outlives the test.
  await tester.runAsync(() => CompanionCatalog.instance.allStops());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
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

void _expectCamera(WidgetTester tester, LatLng center, double zoom) {
  final cam = _camera(tester);
  expect(cam.center.latitude, closeTo(center.latitude, 1e-6));
  expect(cam.center.longitude, closeTo(center.longitude, 1e-6));
  expect(cam.zoom, closeTo(zoom, 1e-6));
}

int _requests(FakeGeolocator geo) =>
    geo.calls.where((c) => c == 'requestPermission').length;

void main() {
  usePackTestEnv(prefix: 'rotransit_launch_location_');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => CompanionCatalog.instance.reset());

  testWidgets(
      'permission already granted: launch centers on the rider at street '
      'zoom and starts the live stream, without asking', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _whileInUse
      ..install(tester);
    await _pumpMap(tester);

    expect(_requests(geo), 0);
    _expectCamera(tester, _fix, 16);
    expect(userDot(tester), _fix);
    expect(geo.sink, isNotNull, reason: 'live stream listening');
    expect((geo.listenArgs.single as Map)['distanceFilter'], 15);
  });

  testWidgets(
      'permission undecided and granted at the launch prompt: asked once, '
      'then centered with the stream on', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: true)..install(tester);
    await _pumpMap(tester);

    expect(_requests(geo), 1);
    _expectCamera(tester, _fix, 16);
    expect(geo.sink, isNotNull);
  });

  testWidgets(
      'permission undecided and refused at the launch prompt: default view, '
      'no stream, no message, and the next launch does not ask again',
      (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)..install(tester);
    await _pumpMap(tester);

    expect(_requests(geo), 1);
    _expectCamera(tester, _default, 15);
    expect(geo.listenArgs, isEmpty);
    expect(userDot(tester), isNull);
    expect(find.byType(SnackBar), findsNothing);

    // Next launch (same stored preferences).
    await tester.pumpWidget(const SizedBox());
    await _pumpMap(tester);
    expect(_requests(geo), 1, reason: 'the launch prompt is shown only once');
    _expectCamera(tester, _default, 15);
    expect(geo.listenArgs, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'permission denied forever: no prompt, default view, no stream, '
      'no message', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _deniedForever
      ..install(tester);
    await _pumpMap(tester);

    expect(_requests(geo), 0);
    expect(geo.calls, isNot(contains('getCurrentPosition')));
    _expectCamera(tester, _default, 15);
    expect(geo.listenArgs, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'location services off at launch: no prompt and the launch prompt is '
      'kept; the next launch with services on asks', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: true)
      ..serviceEnabled = false
      ..install(tester);
    await _pumpMap(tester);

    expect(_requests(geo), 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('map_launch_location_prompted'), isNull);
    _expectCamera(tester, _default, 15);
    expect(find.byType(SnackBar), findsNothing);

    // Next launch, location switched on.
    geo.serviceEnabled = true;
    await tester.pumpWidget(const SizedBox());
    await _pumpMap(tester);
    expect(_requests(geo), 1);
    expect(prefs.getBool('map_launch_location_prompted'), isTrue);
    _expectCamera(tester, _fix, 16);
  });

  testWidgets(
      'a slow launch fix does not move the camera off a stop the app opened '
      'meanwhile', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _whileInUse
      ..holdPosition = Completer<void>()
      ..install(tester);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await _pumpMap(tester, container: c);
    expect(geo.calls, contains('getCurrentPosition'));

    // A stop about 2 km from the rider's fix.
    final stops =
        await tester.runAsync(() => CompanionCatalog.instance.allStops());
    const dist = Distance();
    final stop = stops!.firstWhere(
        (s) => dist.as(LengthUnit.Meter, _fix, LatLng(s.lat, s.lon)) > 2000);
    c.read(companionFocusStopProvider.notifier).state = stop;
    await settleLocation(tester);
    expect(find.byType(StopBoardSheet), findsOneWidget);
    final onStop = _camera(tester);

    geo.holdPosition!.complete();
    await settleLocation(tester);
    expect(userDot(tester), _fix);
    expect(geo.sink, isNotNull, reason: 'the stream still starts');
    _expectCamera(tester, LatLng(stop.lat, stop.lon), onStop.zoom);
  });

  testWidgets(
      'center-on-me during a slow launch fix: the camera ends at the '
      'center-on-me zoom, not the launch zoom', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)
      ..permission = _whileInUse
      ..holdPosition = Completer<void>()
      ..install(tester);
    await _pumpMap(tester);

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    geo.holdPosition!.complete();
    await settleLocation(tester);

    _expectCamera(tester, _fix, 15.5);
    expect(geo.sink, isNotNull);
  });
}
