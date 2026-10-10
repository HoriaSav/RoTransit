import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

Future<void> _pumpMap(WidgetTester tester) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
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

void main() {
  usePackTestEnv(prefix: 'rotransit_live_platform_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'first tap asks for permission once, then the dot follows a 15 m '
      'position stream that stops in the background and on dispose',
      (tester) async {
    // The one-time launch prompt was already used (and refused), so launch
    // only checks the permission and leaves location alone.
    SharedPreferences.setMockInitialValues(
        {'map_launch_location_prompted': true});
    final geo = FakeGeolocator(grantOnRequest: true)..install(tester);
    await _pumpMap(tester);
    expect(geo.calls, ['checkPermission'],
        reason: 'launch only checks the permission; no prompt, no position');
    expect(geo.listenArgs, isEmpty);

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    expect(geo.calls.where((c) => c == 'requestPermission'), hasLength(1));
    expect(userDot(tester), const LatLng(45.6427, 25.5887));
    expect(geo.sink, isNotNull, reason: 'live stream should be listening');
    expect((geo.listenArgs.last as Map)['distanceFilter'], 15);

    geo.sink!.success(fakePosition(45.6500, 25.6000));
    await settleLocation(tester);
    expect(userDot(tester), const LatLng(45.6500, 25.6000));

    // A second tap recenters without prompting again.
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    expect(geo.calls.where((c) => c == 'requestPermission'), hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settleLocation(tester);
    expect(geo.sink, isNull, reason: 'stream must stop in the background');
    final cancelsInBackground = geo.cancels;
    expect(cancelsInBackground, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleLocation(tester);
    expect(geo.sink, isNotNull, reason: 'stream resumes in the foreground');
    geo.sink!.success(fakePosition(45.6600, 25.6100));
    await settleLocation(tester);
    expect(userDot(tester), const LatLng(45.6600, 25.6100));

    await tester.pumpWidget(const SizedBox());
    await settleLocation(tester);
    expect(geo.sink, isNull, reason: 'stream must stop on dispose');
    expect(geo.cancels, greaterThan(cancelsInBackground));
  });

  testWidgets('denied on the first tap: warning, no dot, no stream',
      (tester) async {
    final geo = FakeGeolocator(grantOnRequest: false)..install(tester);
    await _pumpMap(tester);

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    expect(geo.calls, contains('requestPermission'));
    expect(geo.calls, isNot(contains('getCurrentPosition')));
    expect(geo.listenArgs, isEmpty);
    expect(userDot(tester), isNull);
    expect(find.text('Location permission was denied.'), findsOneWidget);
  });
}
