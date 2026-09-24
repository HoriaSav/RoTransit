import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/presentation/map_companion_tab.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';

void main() {
  testWidgets(
      'Settings gear tap sets settingsOpenProvider (not blocked by IgnorePointer)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: MapCompanionTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(settingsOpenProvider), isFalse);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();

    expect(
      container.read(settingsOpenProvider),
      isTrue,
      reason: 'Outer IgnorePointer(ignoring:true) would swallow this tap',
    );
  });
}
