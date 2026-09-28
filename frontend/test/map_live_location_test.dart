import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/location/live_position_source.dart';
import 'package:rotransit/src/core/location/user_location_provider.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

class _FixLocation extends UserLocationNotifier {
  @override
  Future<UserLocationState> resolve({bool forceFresh = false}) async {
    state = const UserLocationState(
        lat: 45.6427, lon: 25.5887, accuracyM: 10, resolveFinished: true);
    return state;
  }
}

/// Fake Geolocator: counts listeners, lets the test push positions.
class _FakePositions implements LivePositionSource {
  _FakePositions({this.granted = true});

  final bool granted;
  StreamController<LivePosition>? controller;
  int listens = 0;
  int cancels = 0;

  bool get listening => controller != null;

  @override
  Future<bool> canFollow() async => granted;

  @override
  Stream<LivePosition> positions() {
    final c = StreamController<LivePosition>();
    c.onListen = () {
      listens++;
      controller = c;
    };
    c.onCancel = () {
      cancels++;
      controller = null;
    };
    return c.stream;
  }

  void emit(double lat, double lon) => controller!.add((lat: lat, lon: lon));

  void fail(Object error) => controller!.addError(error);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

LatLng? _dot(WidgetTester tester) {
  for (final layer in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer))) {
    for (final m in layer.markers) {
      if (m.width == 18 && m.height == 18) return m.point;
    }
  }
  return null;
}

void main() {
  usePackTestEnv(prefix: 'rotransit_live_location_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpMap(
      WidgetTester tester, _FakePositions fake) async {
    final c = ProviderContainer(overrides: [
      userLocationProvider.overrideWith((ref) => _FixLocation()),
      livePositionSourceProvider.overrideWithValue(fake),
    ]);
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
    await _settle(tester);
    return c;
  }

  testWidgets(
      'launch prompt already used, permission not granted: no live updates '
      'or dot before the first center-on-me tap', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'map_launch_location_prompted': true});
    final fake = _FakePositions(granted: false);
    await pumpMap(tester, fake);
    expect(fake.listens, 0);
    expect(_dot(tester), isNull);
  });

  testWidgets('after the tap the dot follows the position stream',
      (tester) async {
    final fake = _FakePositions();
    await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listening, isTrue);
    expect(_dot(tester), const LatLng(45.6427, 25.5887));

    fake.emit(45.6500, 25.6000);
    await _settle(tester);
    expect(_dot(tester), const LatLng(45.6500, 25.6000));

    fake.emit(45.6600, 25.6100);
    await _settle(tester);
    expect(_dot(tester), const LatLng(45.6600, 25.6100));
  });

  testWidgets('updates pause in the background and resume in the foreground',
      (tester) async {
    final fake = _FakePositions();
    await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listening, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester);
    expect(fake.listening, isFalse);
    expect(fake.cancels, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(fake.listening, isTrue);
    expect(fake.listens, 2);
  });

  testWidgets('the subscription is cancelled when the map is disposed',
      (tester) async {
    final fake = _FakePositions();
    await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listening, isTrue);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    expect(fake.listening, isFalse);
    expect(fake.cancels, 1);
  });

  testWidgets('without permission there is no stream', (tester) async {
    final fake = _FakePositions(granted: false);
    await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listens, 0);
  });

  testWidgets('updates stop while another tab is shown and resume on the map',
      (tester) async {
    final fake = _FakePositions();
    final c = await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listening, isTrue);

    for (final tab in [1, 2]) {
      c.read(selectedTabProvider.notifier).state = tab;
      await _settle(tester);
      expect(fake.listening, isFalse, reason: 'tab $tab');
    }
    c.read(selectedTabProvider.notifier).state = 0;
    await _settle(tester);
    expect(fake.listening, isTrue);
    expect(fake.listens, 2);
  });

  testWidgets('updates stop while Settings is open over the map',
      (tester) async {
    final fake = _FakePositions();
    final c = await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(fake.listening, isTrue);

    c.read(settingsOpenProvider.notifier).state = true;
    await _settle(tester);
    expect(fake.listening, isFalse);

    // Back from the background while Settings is still open: stay off.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(fake.listening, isFalse);

    c.read(settingsOpenProvider.notifier).state = false;
    await _settle(tester);
    expect(fake.listening, isTrue);
  });

  testWidgets('permission revoked: the dot goes away and the hint is shown',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => switch (call.method) {
        'isLocationServiceEnabled' => true,
        'checkPermission' => 0, // denied
        _ => null,
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'), null));
    final fake = _FakePositions();
    await pumpMap(tester, fake);
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(_dot(tester), isNotNull);

    fake.fail(StateError('permission revoked'));
    await _settle(tester);
    expect(fake.listening, isFalse);
    expect(_dot(tester), isNull);
    expect(find.text('Location permission was denied.'), findsOneWidget);
  });
}
