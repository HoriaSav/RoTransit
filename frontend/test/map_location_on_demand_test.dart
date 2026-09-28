import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/location/user_location_provider.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/presentation/map_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_test_env.dart';

/// Counts resolve() calls and answers with a fix in central Brașov.
class _SpyLocation extends UserLocationNotifier {
  int resolveCalls = 0;

  @override
  Future<UserLocationState> resolve({bool forceFresh = false}) async {
    resolveCalls++;
    state = const UserLocationState(
        lat: 45.6427, lon: 25.5887, accuracyM: 10, resolveFinished: true);
    return state;
  }
}

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  usePackTestEnv(prefix: 'rotransit_location_');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the map never asks for location until center-on-me is tapped',
      (tester) async {
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _geolocator,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocator, null));

    final spy = _SpyLocation();
    final c = ProviderContainer(
      overrides: [userLocationProvider.overrideWith((ref) => spy)],
    );
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

    expect(spy.resolveCalls, 0, reason: 'no location request at startup');
    expect(platformCalls, isEmpty,
        reason: 'no Geolocator permission/position call at startup');

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await _settle(tester);
    expect(spy.resolveCalls, 1);
  });
}
