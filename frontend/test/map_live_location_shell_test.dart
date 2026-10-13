import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/shell/main_shell.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_geolocator.dart';
import 'support/pack_test_env.dart';

// The real shell with real nav-bar and Settings taps: GPS updates must run
// only while the map is the screen the rider is looking at.
Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainShell(),
      ),
    ),
  );
  await settleLocation(tester);
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleLocation(tester);
}

void main() {
  usePackTestEnv(prefix: 'rotransit_live_shell_');
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

  testWidgets(
      'GPS stream stops on the Timetable, Favorites and Settings screens and '
      'restarts only when the map is visible again', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: true)..install(tester);
    await _pumpShell(tester);

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    expect(geo.sink, isNotNull, reason: 'following after the first tap');
    final listens = geo.listenArgs.length;

    await _tapNav(tester, 'Timetable');
    expect(geo.sink, isNull, reason: 'no GPS while Timetable is shown');
    await _tapNav(tester, 'Favorites');
    expect(geo.sink, isNull, reason: 'no GPS while Favorites is shown');
    expect(geo.listenArgs.length, listens, reason: 'no re-listen off-map');

    await _tapNav(tester, 'Map');
    expect(geo.sink, isNotNull, reason: 'GPS back when the map is visible');
    expect((geo.listenArgs.last as Map)['distanceFilter'], 15);
    geo.sink!.success(fakePosition(45.6500, 25.6000));
    await settleLocation(tester);
    expect(userDot(tester), const LatLng(45.6500, 25.6000));

    await tester.tap(find.byTooltip('Settings'));
    await settleLocation(tester);
    expect(geo.sink, isNull, reason: 'no GPS while Settings covers the map');
    await tester.tap(find.byTooltip('Back'));
    await settleLocation(tester);
    expect(geo.sink, isNotNull, reason: 'GPS back after leaving Settings');
  });

  testWidgets(
      'returning from the background on another tab does not restart GPS; '
      'switching back to the map does', (tester) async {
    final geo = FakeGeolocator(grantOnRequest: true)..install(tester);
    await _pumpShell(tester);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await settleLocation(tester);
    expect(geo.sink, isNotNull);

    await _tapNav(tester, 'Timetable');
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settleLocation(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleLocation(tester);
    expect(geo.sink, isNull, reason: 'resumed on Timetable: GPS stays off');

    await _tapNav(tester, 'Map');
    expect(geo.sink, isNotNull, reason: 'map visible again: GPS on');
  });
}
